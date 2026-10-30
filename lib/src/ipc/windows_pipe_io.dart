import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Thrown by [PipeIo] when the pipe can no longer carry data, typically
/// because Discord exited or dropped the connection.
class PipeIoException implements Exception {
  const PipeIoException(this.message);

  final String message;

  @override
  String toString() => 'PipeIoException: $message';
}

/// Named-pipe I/O that never waits on the other end of the pipe.
///
/// One read and one write may be outstanding at a time. Completion is
/// observed by polling, so a stalled Discord can delay data but never the
/// calling isolate.
abstract interface class PipeIo {
  /// Connects to pipe number [index]. Returns false when it is unavailable.
  bool open(int index);

  /// Starts a read. Throws [PipeIoException] if it cannot be started.
  void startRead();

  /// The bytes of the finished read, or null while it is still pending.
  /// Throws [PipeIoException] if the read failed.
  Uint8List? pollRead();

  /// Starts writing [bytes]. Throws [PipeIoException] if it cannot be started.
  void startWrite(Uint8List bytes);

  /// True once the write has finished, false while it is still pending.
  /// Throws [PipeIoException] if the write failed.
  bool pollWrite();

  /// Cancels outstanding I/O, closes the pipe, and releases native memory.
  void close();
}

// NTSTATUS values the kernel stores in OVERLAPPED.Internal.
const _statusCancelled = 0xC0000120;
const _statusBufferOverflow = 0x80000005;

/// Synchronous pipe failures after which no I/O is queued, so the operation's
/// memory is ours again. Other failures are treated as possibly queued:
/// [Win32PipeIo.close] cancels the operation and leaks its memory if it never
/// finishes.
const _syncPipeFailures = {
  ERROR_INVALID_HANDLE,
  ERROR_BROKEN_PIPE,
  ERROR_NO_DATA,
  ERROR_PIPE_NOT_CONNECTED,
};

/// Upper bound on waiting for cancelled I/O to finish during [close].
/// NPFS completes cancelled requests immediately; this only guards the
/// isolate against a misbehaving filter driver.
const _cancelWaitMs = 100;

/// [PipeIo] over a Win32 named pipe opened with FILE_FLAG_OVERLAPPED.
///
/// Every Win32 call here returns immediately: reads and writes are
/// overlapped, completion is checked with a zero-timeout wait on each
/// operation's event, and nothing calls FlushFileBuffers (which waits until
/// the server has read everything written).
class Win32PipeIo implements PipeIo {
  Win32PipeIo({this.pipeNamePrefix = r'\\.\pipe\discord-ipc-'});

  /// Pipe path without the trailing index.
  final String pipeNamePrefix;

  static const _readBufferSize = 16 * 1024;

  HANDLE _handle = HANDLE(nullptr);
  HANDLE _readEvent = HANDLE(nullptr);
  HANDLE _writeEvent = HANDLE(nullptr);
  Pointer<OVERLAPPED> _readOverlapped = nullptr;
  Pointer<OVERLAPPED> _writeOverlapped = nullptr;
  Pointer<Uint8> _readBuffer = nullptr;
  Pointer<Uint8> _writeBuffer = nullptr;
  int _writeLength = 0;
  bool _readPending = false;
  bool _writePending = false;

  @override
  bool open(int index) {
    final path = '$pipeNamePrefix$index'.toNativeUtf16();
    try {
      _handle = CreateFile(
        PCWSTR(path),
        GENERIC_READ | GENERIC_WRITE,
        const FILE_SHARE_MODE(0),
        null,
        OPEN_EXISTING,
        FILE_FLAG_OVERLAPPED,
        null,
      ).value;
    } finally {
      free(path);
    }
    if (!_handle.isValid) return false;

    _readEvent = CreateEvent(null, true, false, null).value;
    _writeEvent = CreateEvent(null, true, false, null).value;
    _readOverlapped = calloc<OVERLAPPED>();
    _writeOverlapped = calloc<OVERLAPPED>();
    _readBuffer = calloc<Uint8>(_readBufferSize);
    if (!_readEvent.isValid || !_writeEvent.isValid) {
      close();
      return false;
    }
    return true;
  }

  @override
  void startRead() {
    _prepare(_readOverlapped, _readEvent);
    // Pending until proven otherwise; see _syncPipeFailures.
    _readPending = true;
    final result = ReadFile(
      _handle,
      _readBuffer,
      _readBufferSize,
      null,
      _readOverlapped,
    );
    if (!result.value) {
      final error = result.error;
      if (error == ERROR_IO_PENDING) return;
      if (_syncPipeFailures.contains(error)) _readPending = false;
      throw _startFailure(error, 'read');
    }
  }

  @override
  Uint8List? pollRead() {
    if (!_readPending || !_isSignaled(_readEvent)) return null;
    _readPending = false;
    final status = _statusOf(_readOverlapped);
    final count = _readOverlapped.ref.InternalHigh;
    if (status == 0 || status == _statusBufferOverflow) {
      return Uint8List.fromList(_readBuffer.asTypedList(count));
    }
    if (status == _statusCancelled) {
      // Not ours: Windows cancels a thread's pending I/O when that thread
      // exits, and plain Dart isolates hop between pool threads.
      startRead();
      return null;
    }
    throw _ntStatusException(status, 'read');
  }

  @override
  void startWrite(Uint8List bytes) {
    _writeBuffer = calloc<Uint8>(bytes.length);
    _writeBuffer.asTypedList(bytes.length).setAll(0, bytes);
    _writeLength = bytes.length;
    _issueWrite();
  }

  void _issueWrite() {
    _prepare(_writeOverlapped, _writeEvent);
    // Pending until proven otherwise; see _syncPipeFailures.
    _writePending = true;
    final result = WriteFile(
      _handle,
      _writeBuffer,
      _writeLength,
      null,
      _writeOverlapped,
    );
    if (!result.value) {
      final error = result.error;
      if (error == ERROR_IO_PENDING) return;
      if (_syncPipeFailures.contains(error)) {
        _writePending = false;
        _releaseWriteBuffer();
      }
      throw _startFailure(error, 'write');
    }
  }

  @override
  bool pollWrite() {
    if (!_writePending) return true;
    if (!_isSignaled(_writeEvent)) return false;
    _writePending = false;
    final status = _statusOf(_writeOverlapped);
    final count = _writeOverlapped.ref.InternalHigh;
    if (status == _statusCancelled && count == 0) {
      // Issuing thread exited before any byte moved; see pollRead.
      _issueWrite();
      return false;
    }
    final expected = _writeLength;
    _releaseWriteBuffer();
    if (status != 0) throw _ntStatusException(status, 'write');
    if (count != expected) {
      throw PipeIoException('Short write: $count of $expected bytes');
    }
    return true;
  }

  @override
  void close() {
    var readDone = !_readPending;
    var writeDone = !_writePending;
    if (_handle.isValid) {
      if (!readDone || !writeDone) {
        CancelIoEx(_handle, null);
        if (!readDone) readDone = _awaitCancel(_readEvent);
        if (!writeDone) writeDone = _awaitCancel(_writeEvent);
      }
      CloseHandle(_handle);
      _handle = HANDLE(nullptr);
    }
    // The kernel keeps its own reference to an event, so closing these is
    // safe even if an operation outlived the cancel wait.
    if (_readEvent.isValid) CloseHandle(_readEvent);
    if (_writeEvent.isValid) CloseHandle(_writeEvent);
    _readEvent = HANDLE(nullptr);
    _writeEvent = HANDLE(nullptr);
    _readPending = false;
    _writePending = false;

    // Memory the kernel may still write to is leaked rather than freed.
    if (readDone) {
      _free(_readOverlapped);
      _free(_readBuffer);
    }
    if (writeDone) {
      _free(_writeOverlapped);
      _releaseWriteBuffer();
    }
    _readOverlapped = nullptr;
    _readBuffer = nullptr;
    _writeOverlapped = nullptr;
    _writeBuffer = nullptr;
  }

  bool _awaitCancel(HANDLE event) =>
      WaitForSingleObject(event, _cancelWaitMs).value == WAIT_OBJECT_0;

  void _releaseWriteBuffer() {
    _free(_writeBuffer);
    _writeBuffer = nullptr;
    _writeLength = 0;
  }

  static void _free(Pointer pointer) {
    if (pointer != nullptr) free(pointer);
  }

  static void _prepare(Pointer<OVERLAPPED> overlapped, HANDLE event) {
    final ref = overlapped.ref;
    ref.Internal = 0;
    ref.InternalHigh = 0;
    ref.Offset = 0;
    ref.OffsetHigh = 0;
    ref.hEvent = event;
  }

  /// The event is set only after the kernel has written Internal and
  /// InternalHigh, so it — not Internal — gates reading the result.
  static bool _isSignaled(HANDLE event) =>
      WaitForSingleObject(event, 0).value == WAIT_OBJECT_0;

  /// NTSTATUS is 32 bits; OVERLAPPED.Internal is pointer-sized.
  static int _statusOf(Pointer<OVERLAPPED> overlapped) =>
      overlapped.ref.Internal & 0xFFFFFFFF;

  static PipeIoException _startFailure(int error, String operation) =>
      PipeIoException('Failed to start $operation: Win32 error $error');

  static PipeIoException _ntStatusException(int status, String operation) =>
      PipeIoException(
        '$operation failed: NTSTATUS 0x${status.toRadixString(16)}',
      );
}
