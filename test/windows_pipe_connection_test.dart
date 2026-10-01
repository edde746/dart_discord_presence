import 'dart:async';
import 'dart:typed_data';

import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:dart_discord_presence/src/ipc/discord_ipc_client.dart';
import 'package:dart_discord_presence/src/ipc/ipc_frame.dart';
import 'package:dart_discord_presence/src/ipc/windows_pipe_connection.dart';
import 'package:dart_discord_presence/src/ipc/windows_pipe_io.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

/// In-memory [PipeIo]. The test plays Discord: [serverWrite] queues bytes for
/// the client to read, and [draining] decides whether client writes finish.
class FakePipeIo implements PipeIo {
  final _incoming = <Uint8List>[];
  final written = <Uint8List>[];
  Uint8List? _inFlightWrite;

  /// Whether a write has started and not yet finished.
  bool get writeInFlight => _inFlightWrite != null;
  bool _readPending = false;
  bool closed = false;

  /// False models a Discord that has stopped reading its end of the pipe.
  bool draining = true;

  /// Thrown by the next [pollRead], e.g. when Discord exits.
  PipeIoException? readFailure;

  /// Thrown by [startRead] calls after the first, i.e. when re-posting a read
  /// once Discord has closed its end.
  PipeIoException? restartFailure;

  /// Thrown by [startWrite], e.g. when the pipe broke after it was opened.
  PipeIoException? writeFailure;

  bool _started = false;

  void serverWrite(Uint8List bytes) => _incoming.add(bytes);

  @override
  bool open(int index) => index == 0;

  @override
  void startRead() {
    final failure = restartFailure;
    if (_started && failure != null) throw failure;
    _started = true;
    _readPending = true;
  }

  @override
  Uint8List? pollRead() {
    final failure = readFailure;
    if (failure != null) throw failure;
    if (!_readPending || _incoming.isEmpty) return null;
    _readPending = false;
    return _incoming.removeAt(0);
  }

  @override
  void startWrite(Uint8List bytes) {
    final failure = writeFailure;
    if (failure != null) throw failure;
    if (_inFlightWrite != null) throw StateError('Overlapping writes');
    _inFlightWrite = bytes;
  }

  @override
  bool pollWrite() {
    if (!draining) return false;
    written.add(_inFlightWrite!);
    _inFlightWrite = null;
    return true;
  }

  @override
  void close() => closed = true;
}

IpcFrame _frame(String payload) =>
    IpcFrame.fromJson(DiscordOpcode.frame, {'p': payload});

Uint8List _ready() => IpcFrame.fromJson(DiscordOpcode.frame, {
  'cmd': 'DISPATCH',
  'evt': 'READY',
  'data': {
    'user': {'id': '1', 'username': 'tester'},
  },
}).toBytes();

void main() {
  test('a write Discord never drains fails after writeTimeout and ends the '
      'frame stream', () {
    fakeAsync((async) {
      final io = FakePipeIo()..draining = false;
      final connection = WindowsPipeConnection(io: io);
      connection.open();
      async.flushMicrotasks();
      var streamDone = false;
      connection.frames.listen(
        null,
        onError: (Object e) => fail('unexpected stream error: $e'),
        onDone: () => streamDone = true,
      );

      Object? sendError;
      connection.sendFrame(_frame('presence')).catchError((Object e) {
        sendError = e;
      });

      async.elapse(const Duration(seconds: 4));
      expect(sendError, isNull);
      expect(connection.isOpen, isTrue);

      async.elapse(const Duration(seconds: 2));
      expect(sendError, isA<DiscordConnectionException>());
      expect(streamDone, isTrue);
      expect(connection.isOpen, isFalse);
      expect(io.closed, isTrue);
    });
  });

  test('queued frames are written one at a time in send order', () {
    fakeAsync((async) {
      final io = FakePipeIo()..draining = false;
      final connection = WindowsPipeConnection(io: io);
      connection.open();
      async.flushMicrotasks();

      final sent = <String>[];
      for (final payload in ['a', 'b', 'c']) {
        connection.sendFrame(_frame(payload)).then((_) => sent.add(payload));
      }
      async.elapse(const Duration(milliseconds: 100));
      expect(sent, isEmpty);

      io.draining = true;
      async.elapse(const Duration(milliseconds: 100));
      expect(sent, ['a', 'b', 'c']);
      expect(
        io.written.map(
          (bytes) => IpcFrameDecoder().add(bytes).single.jsonPayload['p'],
        ),
        ['a', 'b', 'c'],
      );
    });
  });

  test(
    'delivers every frame from reads that completed since the last poll',
    () {
      fakeAsync((async) {
        final io = FakePipeIo();
        final connection = WindowsPipeConnection(io: io);
        connection.open();
        async.flushMicrotasks();
        final received = <Object?>[];
        connection.frames.listen((f) => received.add(f.jsonPayload['p']));

        final one = _frame('one').toBytes();
        final two = _frame('two').toBytes();
        io.serverWrite(Uint8List.fromList([...one, ...two.take(3)]));
        io.serverWrite(Uint8List.sublistView(two, 3));
        async.elapse(const Duration(milliseconds: 20));

        expect(received, ['one', 'two']);
      });
    },
  );

  test('Discord closing the pipe ends the frame stream without an error', () {
    fakeAsync((async) {
      final io = FakePipeIo();
      final connection = WindowsPipeConnection(io: io);
      connection.open();
      async.flushMicrotasks();
      var streamDone = false;
      connection.frames.listen(
        null,
        onError: (Object e) => fail('unexpected stream error: $e'),
        onDone: () => streamDone = true,
      );

      io.readFailure = const PipeIoException('read failed: pipe broken');
      async.elapse(const Duration(milliseconds: 20));

      expect(streamDone, isTrue);
      expect(connection.isOpen, isFalse);
      expect(io.closed, isTrue);
    });
  });

  test('frames read just before Discord closes the pipe are delivered before '
      'the stream ends', () {
    fakeAsync((async) {
      final io = FakePipeIo();
      final connection = WindowsPipeConnection(io: io);
      connection.open();
      async.flushMicrotasks();
      final events = <Object?>[];
      connection.frames.listen(
        (f) => events.add(f.jsonPayload['p']),
        onError: (Object e) => fail('unexpected stream error: $e'),
        onDone: () => events.add('done'),
      );

      io.serverWrite(_frame('last').toBytes());
      io.restartFailure = const PipeIoException('read failed: pipe broken');
      async.elapse(const Duration(milliseconds: 20));

      expect(events, ['last', 'done']);
      expect(connection.isOpen, isFalse);
    });
  });

  // Real time, not fakeAsync: StreamSubscription.cancel() inside the client
  // completes on the root zone, which fakeAsync cannot drive.
  test('a Discord that stops reading surfaces as a disconnect event, not a '
      'hang', () async {
    final io = FakePipeIo();
    final client = DiscordIpcClient(
      connectionFactory: () => WindowsPipeConnection(
        io: io,
        writeTimeout: const Duration(milliseconds: 50),
      ),
    );
    final disconnected = client.events.firstWhere(
      (e) => e is DiscordDisconnectedEvent,
    );

    final connecting = client.connect('app');
    io.serverWrite(_ready());
    await connecting.timeout(const Duration(seconds: 2));

    io.draining = false;
    await client.clearPresence().timeout(const Duration(seconds: 2));
    await disconnected.timeout(const Duration(seconds: 2));
    expect(client.isConnected, isFalse);
  });

  test('connect completes when READY arrives in the same poll that finishes '
      'the handshake write', () async {
    // Discord leaves the handshake unread for a moment, then answers: one poll
    // drains READY first and only then sees the write finish.
    final io = FakePipeIo()..draining = false;
    final client = DiscordIpcClient(
      connectionFactory: () => WindowsPipeConnection(io: io),
    );

    final connecting = client.connect('app');
    while (!io.writeInFlight) {
      await Future<void>.delayed(Duration.zero);
    }
    io.serverWrite(_ready());
    io.draining = true;
    await connecting.timeout(const Duration(seconds: 2));

    expect(client.isConnected, isTrue);
    await client.disconnect();
  });

  test('a handshake write that fails fails connect without an uncaught '
      'error', () async {
    final uncaught = <Object>[];
    Object? connectError;
    await runZonedGuarded(() async {
      final io = FakePipeIo()
        ..writeFailure = const PipeIoException('write failed: pipe broken');
      final client = DiscordIpcClient(
        connectionFactory: () => WindowsPipeConnection(io: io),
      );
      try {
        await client.connect('app').timeout(const Duration(seconds: 2));
      } catch (e) {
        connectError = e;
      }
      // Let any stray error from the closed connection surface.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (error, _) => uncaught.add(error));

    expect(connectError, isA<DiscordConnectionException>());
    expect(uncaught, isEmpty);
  });
}
