import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../exceptions/discord_rpc_exception.dart';
import 'ipc_connection.dart';
import 'ipc_frame.dart';

/// Unix domain socket connection for macOS and Linux.
///
/// Discord creates IPC sockets at:
/// - Linux: $XDG_RUNTIME_DIR/discord-ipc-N
/// - macOS: $TMPDIR/discord-ipc-N
/// - Fallback: /tmp/discord-ipc-N
class UnixSocketConnection implements IpcConnection {
  Socket? _socket;
  final _frameController = StreamController<IpcFrame>.broadcast();
  final _buffer = BytesBuilder(copy: false);
  bool _isOpen = false;

  @override
  bool get isOpen => _isOpen;

  @override
  Stream<IpcFrame> get frames => _frameController.stream;

  @override
  Future<void> open() async {
    // Try sockets 0-9
    for (int i = 0; i < 10; i++) {
      final path = _getSocketPath(i);
      try {
        _socket = await Socket.connect(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
        );
        _isOpen = true;
        _startListening();
        return;
      } on SocketException {
        // Try next socket
        continue;
      }
    }
    throw const DiscordNotRunningException();
  }

  String _getSocketPath(int index) {
    // Check XDG_RUNTIME_DIR first (Linux)
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    if (runtimeDir != null && runtimeDir.isNotEmpty) {
      return '$runtimeDir/discord-ipc-$index';
    }

    // Then TMPDIR (macOS)
    final tmpDir = Platform.environment['TMPDIR'];
    if (tmpDir != null && tmpDir.isNotEmpty) {
      // Remove trailing slash if present
      final cleanPath = tmpDir.endsWith('/')
          ? tmpDir.substring(0, tmpDir.length - 1)
          : tmpDir;
      return '$cleanPath/discord-ipc-$index';
    }

    // Fallback to /tmp
    return '/tmp/discord-ipc-$index';
  }

  void _startListening() {
    _socket!.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  void _onData(Uint8List data) {
    _buffer.add(data);
    _tryParseFrames();
  }

  void _tryParseFrames() {
    while (true) {
      final bytes = _buffer.toBytes();

      // Need at least header size
      if (bytes.length < IpcFrame.headerSize) break;

      // Parse header
      final header = IpcFrame.parseHeader(bytes);
      if (header == null) break;

      // Validate payload size
      if (header.length > IpcFrame.maxPayloadSize) {
        _frameController.addError(
          const DiscordProtocolException('Frame payload too large'),
        );
        close();
        return;
      }

      // Check if we have the complete frame
      final totalFrameSize = IpcFrame.headerSize + header.length;
      if (bytes.length < totalFrameSize) break;

      // Extract payload
      final payload = Uint8List.fromList(
        bytes.sublist(IpcFrame.headerSize, totalFrameSize),
      );

      final frame = IpcFrame(opcode: header.opcode, payload: payload);

      // Clear buffer and add remaining bytes
      _buffer.clear();
      if (bytes.length > totalFrameSize) {
        _buffer.add(bytes.sublist(totalFrameSize));
      }

      _frameController.add(frame);
    }
  }

  void _onError(Object error) {
    if (!_frameController.isClosed) {
      _frameController.addError(
        DiscordConnectionException('Socket error: $error'),
      );
    }
    close();
  }

  void _onDone() {
    _isOpen = false;
    if (!_frameController.isClosed) {
      _frameController.close();
    }
  }

  @override
  Future<void> sendFrame(IpcFrame frame) async {
    if (!_isOpen || _socket == null) {
      throw const DiscordStateException('Connection not open');
    }
    _socket!.add(frame.toBytes());
    await _socket!.flush();
  }

  @override
  Future<void> close() async {
    _isOpen = false;
    _buffer.clear();
    await _socket?.close();
    _socket = null;
  }
}
