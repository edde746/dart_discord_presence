import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../exceptions/discord_rpc_exception.dart';
import 'ipc_connection.dart';
import 'ipc_frame.dart';
import 'windows_pipe_io.dart';

/// Windows named pipe connection for Discord IPC.
///
/// Discord creates named pipes at: \\.\pipe\discord-ipc-N
///
/// Pipe I/O is overlapped and polled (see [PipeIo]), so a Discord client that
/// stops reading or writing delays presence updates but never blocks the
/// calling isolate, which in a Flutter app is the UI isolate.
class WindowsPipeConnection implements IpcConnection {
  WindowsPipeConnection({
    PipeIo? io,
    this.writeTimeout = const Duration(seconds: 5),
    this.pollInterval = const Duration(milliseconds: 16),
  }) : _io = io ?? Win32PipeIo();

  /// How long a frame may wait for Discord to drain the pipe before the
  /// connection is treated as lost. Writes only wait once Discord has left
  /// a full pipe buffer (64 KiB) unread.
  final Duration writeTimeout;

  /// How often pending reads and writes are checked for completion.
  final Duration pollInterval;

  final PipeIo _io;
  final _frameController = StreamController<IpcFrame>.broadcast();
  final _decoder = IpcFrameDecoder();
  final _writeQueue = Queue<_PendingWrite>();
  _PendingWrite? _inFlight;
  Timer? _writeTimer;
  Timer? _pollTimer;
  bool _isOpen = false;

  @override
  bool get isOpen => _isOpen;

  @override
  Stream<IpcFrame> get frames => _frameController.stream;

  @override
  Future<void> open() async {
    // Try pipes 0-9
    for (var i = 0; i < 10; i++) {
      if (!_io.open(i)) continue;
      try {
        _io.startRead();
      } on PipeIoException {
        _io.close();
        continue;
      }
      _isOpen = true;
      _pollTimer = Timer.periodic(pollInterval, (_) => _poll());
      return;
    }
    throw const DiscordNotRunningException();
  }

  @override
  Future<void> sendFrame(IpcFrame frame) async {
    if (!_isOpen) {
      throw const DiscordStateException('Connection not open');
    }
    final write = _PendingWrite(frame.toBytes());
    _writeQueue.add(write);
    try {
      _pumpWrites();
    } on PipeIoException catch (e) {
      _shutDown(DiscordConnectionException('Failed to write to pipe: $e'));
    }
    return write.done.future;
  }

  void _poll() {
    if (!_isOpen) return;
    try {
      _drainReads();
      _pumpWrites();
    } on PipeIoException catch (e) {
      _shutDown(DiscordConnectionException('Pipe error: $e'));
    } on DiscordProtocolException catch (e) {
      _frameController.addError(e);
      close();
    }
  }

  void _drainReads() {
    while (_isOpen) {
      final bytes = _io.pollRead();
      if (bytes == null) return;
      // Emit before re-posting the read: when Discord writes a last frame and
      // closes the pipe, the re-post fails, and those frames must not be lost.
      for (final frame in _decoder.add(bytes)) {
        _frameController.add(frame);
      }
      _io.startRead();
    }
  }

  /// Finishes the in-flight write if it completed and starts the next queued
  /// one. Frames go out one at a time, in order.
  void _pumpWrites() {
    while (_isOpen) {
      final inFlight = _inFlight;
      if (inFlight != null) {
        if (!_io.pollWrite()) {
          _writeTimer ??= Timer(writeTimeout, _onWriteTimeout);
          return;
        }
        _writeTimer?.cancel();
        _writeTimer = null;
        _inFlight = null;
        inFlight.done.complete();
      }
      if (_writeQueue.isEmpty) return;
      final next = _writeQueue.removeFirst();
      _inFlight = next;
      _io.startWrite(next.bytes);
    }
  }

  void _onWriteTimeout() {
    _writeTimer = null;
    _shutDown(
      DiscordConnectionException(
        'Discord did not read from the pipe within $writeTimeout',
      ),
    );
  }

  @override
  Future<void> close() =>
      _shutDown(const DiscordConnectionException('Connection closed'));

  /// Releases the pipe and fails unsent frames with [error].
  ///
  /// The frames stream is closed before those failures are delivered, so a
  /// listener sees the disconnect before any sender sees its error.
  Future<void> _shutDown(DiscordRPCException error) async {
    _isOpen = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _writeTimer?.cancel();
    _writeTimer = null;
    _io.close();

    final unsent = [?_inFlight, ..._writeQueue];
    _inFlight = null;
    _writeQueue.clear();

    final closed = _frameController.isClosed ? null : _frameController.close();
    for (final write in unsent) {
      write.done.completeError(error);
    }
    await closed;
  }
}

class _PendingWrite {
  _PendingWrite(this.bytes);

  final Uint8List bytes;
  final done = Completer<void>();
}
