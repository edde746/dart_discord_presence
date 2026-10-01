@TestOn('windows')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:dart_discord_presence/src/ipc/ipc_frame.dart';
import 'package:dart_discord_presence/src/ipc/windows_pipe_connection.dart';
import 'package:dart_discord_presence/src/ipc/windows_pipe_io.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:win32/win32.dart';

/// Unique per run so a real Discord's discord-ipc-N pipes are never touched.
final _prefix = '\\\\.\\pipe\\dart_discord_presence_test_${pid}_';

/// Server end of a test pipe, standing in for Discord. It reads only when
/// told to, so a test can model a Discord that stopped draining the pipe.
class _Server {
  _Server({int bufferSize = 4096}) {
    final name = '${_prefix}0'.toNativeUtf16();
    try {
      _handle = CreateNamedPipe(
        name,
        PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
        1,
        bufferSize,
        bufferSize,
        0,
        nullptr,
      );
    } finally {
      free(name);
    }
    if (_handle == INVALID_HANDLE_VALUE) {
      throw StateError('CreateNamedPipe failed');
    }
  }

  late int _handle;

  void write(List<int> bytes) {
    final buffer = calloc<Uint8>(bytes.length);
    final count = calloc<DWORD>();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      if (WriteFile(_handle, buffer, bytes.length, count, nullptr) == FALSE) {
        throw StateError('server write failed');
      }
    } finally {
      free(buffer);
      free(count);
    }
  }

  /// Only call once the client's write has completed; blocks otherwise.
  Uint8List read(int max) {
    final buffer = calloc<Uint8>(max);
    final count = calloc<DWORD>();
    try {
      if (ReadFile(_handle, buffer, max, count, nullptr) == FALSE) {
        throw StateError('server read failed');
      }
      return Uint8List.fromList(buffer.asTypedList(count.value));
    } finally {
      free(buffer);
      free(count);
    }
  }

  void close() {
    if (_handle == INVALID_HANDLE_VALUE) return;
    CloseHandle(_handle);
    _handle = INVALID_HANDLE_VALUE;
  }
}

/// Polls [check] until it returns non-null, yielding to the event loop.
Future<T> _eventually<T>(T? Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (true) {
    final value = check();
    if (value != null) return value;
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late _Server server;
  late Win32PipeIo io;

  setUp(() {
    server = _Server();
    io = Win32PipeIo(pipeNamePrefix: _prefix);
    addTearDown(server.close);
    addTearDown(io.close);
  });

  test('reads what Discord writes and writes what Discord reads', () async {
    expect(io.open(0), isTrue);
    io.startRead();

    server.write([1, 2, 3]);
    expect(await _eventually(io.pollRead), [1, 2, 3]);

    io.startWrite(Uint8List.fromList([4, 5]));
    expect(await _eventually(() => io.pollWrite() ? true : null), isTrue);
    expect(server.read(16), [4, 5]);
  });

  test('writes to a Discord that never reads stay pending instead of '
      'blocking the isolate', () async {
    expect(io.open(0), isTrue);
    io.startRead();

    final chunk = Uint8List(1024);
    final elapsed = Stopwatch()..start();
    var pending = false;
    for (var i = 0; i < 64 && !pending; i++) {
      io.startWrite(chunk);
      pending = !io.pollWrite();
    }
    expect(pending, isTrue, reason: 'the 4 KiB pipe buffer should fill');
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(io.pollWrite(), isFalse);

    final closing = Stopwatch()..start();
    io.close();
    expect(closing.elapsed, lessThan(const Duration(milliseconds: 500)));
  });

  test('Discord closing its end fails the pending read', () async {
    expect(io.open(0), isTrue);
    io.startRead();

    server.close();

    await expectLater(
      _eventually(io.pollRead),
      throwsA(isA<PipeIoException>()),
    );
  });

  test('a stalled Discord fails sends after writeTimeout while the event '
      'loop keeps running', () async {
    io.close();
    final connection = WindowsPipeConnection(
      io: Win32PipeIo(pipeNamePrefix: _prefix),
      writeTimeout: const Duration(milliseconds: 500),
    );
    addTearDown(connection.close);
    await connection.open();

    var ticks = 0;
    final ticker = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => ticks++,
    );
    addTearDown(ticker.cancel);

    final frame = IpcFrame(
      opcode: DiscordOpcode.frame,
      payload: Uint8List(2000),
    );
    Object? error;
    await Future.wait([
      for (var i = 0; i < 8; i++)
        connection.sendFrame(frame).catchError((Object e) {
          error ??= e;
        }),
    ]).timeout(const Duration(seconds: 5));

    expect(error, isA<DiscordConnectionException>());
    expect(connection.isOpen, isFalse);
    expect(ticks, greaterThan(20));
  });
}
