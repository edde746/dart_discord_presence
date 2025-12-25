import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../exceptions/discord_rpc_exception.dart';
import 'ipc_connection.dart';
import 'ipc_frame.dart';

/// Windows named pipe connection for Discord IPC.
///
/// Discord creates named pipes at: \\.\pipe\discord-ipc-N
///
/// Uses Win32 API for proper bidirectional pipe access since Dart's
/// File API doesn't support read+write on named pipes.
class WindowsPipeConnection implements IpcConnection {
  int _pipeHandle = INVALID_HANDLE_VALUE;
  final _frameController = StreamController<IpcFrame>.broadcast();
  final _buffer = BytesBuilder(copy: false);
  bool _isOpen = false;
  Timer? _pollTimer;

  @override
  bool get isOpen => _isOpen;

  @override
  Stream<IpcFrame> get frames => _frameController.stream;

  @override
  Future<void> open() async {
    // Try pipes 0-9
    for (int i = 0; i < 10; i++) {
      final path = r'\\.\pipe\discord-ipc-' + i.toString();
      final pathPtr = path.toNativeUtf16();

      try {
        // ignore: deprecated_member_use
        _pipeHandle = CreateFile(
          pathPtr,
          GENERIC_READ | GENERIC_WRITE,
          0, // No sharing
          nullptr, // Default security
          OPEN_EXISTING,
          FILE_ATTRIBUTE_NORMAL,
          NULL,
        );

        free(pathPtr);

        if (_pipeHandle != INVALID_HANDLE_VALUE) {
          _isOpen = true;
          _startPolling();
          return;
        }
      } catch (e) {
        free(pathPtr);
        continue;
      }
    }
    throw const DiscordNotRunningException();
  }

  void _startPolling() {
    // Poll for incoming data every 16ms (~60fps)
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _pollForData(),
    );
  }

  Future<void> _pollForData() async {
    if (!_isOpen || _pipeHandle == INVALID_HANDLE_VALUE) return;

    try {
      // Check if data is available using PeekNamedPipe
      final bytesAvailable = calloc<DWORD>();
      final peekResult = PeekNamedPipe(
        _pipeHandle,
        nullptr,
        0,
        nullptr,
        bytesAvailable,
        nullptr,
      );

      if (peekResult == 0 || bytesAvailable.value == 0) {
        free(bytesAvailable);
        return;
      }

      free(bytesAvailable);

      // Read header if needed
      if (_buffer.length < IpcFrame.headerSize) {
        final needed = IpcFrame.headerSize - _buffer.length;
        final bytes = _readBytes(needed);
        if (bytes.isNotEmpty) {
          _buffer.add(bytes);
        }
      }

      // If we have header, try to read payload
      if (_buffer.length >= IpcFrame.headerSize) {
        final currentBytes = _buffer.toBytes();
        final header = IpcFrame.parseHeader(currentBytes);

        if (header != null) {
          if (header.length > IpcFrame.maxPayloadSize) {
            _frameController.addError(
              const DiscordProtocolException('Frame payload too large'),
            );
            await close();
            return;
          }

          final totalNeeded = IpcFrame.headerSize + header.length;
          if (_buffer.length < totalNeeded) {
            final payloadNeeded = totalNeeded - _buffer.length;
            final bytes = _readBytes(payloadNeeded);
            if (bytes.isNotEmpty) {
              _buffer.add(bytes);
            }
          }

          // Check if we have complete frame
          if (_buffer.length >= totalNeeded) {
            final frameBytes = _buffer.toBytes();
            final payload = Uint8List.fromList(
              frameBytes.sublist(IpcFrame.headerSize, totalNeeded),
            );

            final frame = IpcFrame(opcode: header.opcode, payload: payload);

            // Clear buffer and keep remaining bytes
            _buffer.clear();
            if (frameBytes.length > totalNeeded) {
              _buffer.add(frameBytes.sublist(totalNeeded));
            }

            _frameController.add(frame);
          }
        }
      }
    } catch (e) {
      // Pipe closed or error
      if (_isOpen) {
        _frameController.addError(
          DiscordConnectionException('Pipe error: $e'),
        );
        await close();
      }
    }
  }

  Uint8List _readBytes(int count) {
    if (_pipeHandle == INVALID_HANDLE_VALUE) return Uint8List(0);

    final buffer = calloc<Uint8>(count);
    final bytesRead = calloc<DWORD>();

    try {
      final result = ReadFile(
        _pipeHandle,
        buffer,
        count,
        bytesRead,
        nullptr,
      );

      if (result == 0 || bytesRead.value == 0) {
        return Uint8List(0);
      }

      return Uint8List.fromList(buffer.asTypedList(bytesRead.value));
    } finally {
      free(buffer);
      free(bytesRead);
    }
  }

  @override
  Future<void> sendFrame(IpcFrame frame) async {
    if (!_isOpen || _pipeHandle == INVALID_HANDLE_VALUE) {
      throw const DiscordStateException('Connection not open');
    }

    final bytes = frame.toBytes();
    final buffer = calloc<Uint8>(bytes.length);
    final bytesWritten = calloc<DWORD>();

    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);

      final result = WriteFile(
        _pipeHandle,
        buffer,
        bytes.length,
        bytesWritten,
        nullptr,
      );

      if (result == 0) {
        throw DiscordConnectionException(
          'Failed to write to pipe: ${GetLastError()}',
        );
      }

      // Flush the pipe
      FlushFileBuffers(_pipeHandle);
    } finally {
      free(buffer);
      free(bytesWritten);
    }
  }

  @override
  Future<void> close() async {
    _isOpen = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _buffer.clear();

    if (_pipeHandle != INVALID_HANDLE_VALUE) {
      CloseHandle(_pipeHandle);
      _pipeHandle = INVALID_HANDLE_VALUE;
    }

    if (!_frameController.isClosed) {
      await _frameController.close();
    }
  }
}
