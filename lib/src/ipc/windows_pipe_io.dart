// ignore_for_file: non_constant_identifier_names
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final class OVERLAPPED extends Struct {
  @IntPtr()
  external int Internal;
  @IntPtr()
  external int InternalHigh;
  @Uint32()
  external int Offset;
  @Uint32()
  external int OffsetHigh;
  @IntPtr()
  external int hEvent;
}

const _invalidHandleValue = -1;
const _null = 0;
const _true = 1;
const _false = 0;
const _genericRead = 0x80000000;
const _genericWrite = 0x40000000;
const _openExisting = 3;
const _fileFlagOverlapped = 0x40000000;

final int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
_createFile = _kernel32
    .lookupFunction<
      IntPtr Function(
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Pointer<Void>,
        Uint32,
        Uint32,
        IntPtr,
      ),
      int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
    >('CreateFileW');

final int Function(Pointer<Void>, int, int, Pointer<Utf16>) _createEvent =
    _kernel32.lookupFunction<
      IntPtr Function(Pointer<Void>, Int32, Int32, Pointer<Utf16>),
      int Function(Pointer<Void>, int, int, Pointer<Utf16>)
    >('CreateEventW');

final int Function(
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint32>,
  Pointer<OVERLAPPED>,
)
_readFile = _kernel32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<OVERLAPPED>,
      ),
      int Function(
        int,
        Pointer<Uint8>,
        int,
        Pointer<Uint32>,
        Pointer<OVERLAPPED>,
      )
    >('ReadFile');

final int Function(
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint32>,
  Pointer<OVERLAPPED>,
)
_writeFile = _kernel32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<OVERLAPPED>,
      ),
      int Function(
        int,
        Pointer<Uint8>,
        int,
        Pointer<Uint32>,
        Pointer<OVERLAPPED>,
      )
    >('WriteFile');

final int Function() _getLastError = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetLastError');

final int Function(int, int) _waitForSingleObject = _kernel32
    .lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
      'WaitForSingleObject',
    );

final int Function(int, Pointer<OVERLAPPED>) _cancelIoEx = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<OVERLAPPED>),
      int Function(int, Pointer<OVERLAPPED>)
    >('CancelIoEx');

final int Function(int) _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

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

// Not exported as top-level constants by win32 5.10, the lower bound.
const _errorIoPending = 997;
const _waitObject0 = 0;

/// Synchronous pipe failures after which no I/O is queued, so the operation's
/// memory is ours again. Any other code, including a GetLastError value that
/// another FFI call clobbered (dart-lang/sdk#38832), is treated as possibly
/// queued: the operation stays pending, and [Win32PipeIo.close] cancels it and
/// leaks its memory if it never finishes.
const _syncPipeFailures = {
  6, // ERROR_INVALID_HANDLE
  109, // ERROR_BROKEN_PIPE
  232, // ERROR_NO_DATA
  233, // ERROR_PIPE_NOT_CONNECTED
};

/// Upper bound on waiting for cancelled I/O to finish during [close].
/// NPFS completes cancelled requests immediately; this only guards the
/// isolate against a misbehaving filter driver.
const _cancelWaitMs = 100;

/// [PipeIo] over a Win32 named pipe opened with _fileFlagOverlapped.
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

  int _handle = _invalidHandleValue;
  int _readEvent = _null;
  int _writeEvent = _null;
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
      _handle = _createFile(
        path,
        _genericRead | _genericWrite,
        0,
        nullptr,
        _openExisting,
        _fileFlagOverlapped,
        _null,
      );
    } finally {
      calloc.free(path);
    }
    if (_handle == _invalidHandleValue) return false;

    _readEvent = _createEvent(nullptr, _true, _false, nullptr);
    _writeEvent = _createEvent(nullptr, _true, _false, nullptr);
    _readOverlapped = calloc<OVERLAPPED>();
    _writeOverlapped = calloc<OVERLAPPED>();
    _readBuffer = calloc<Uint8>(_readBufferSize);
    if (_readEvent == _null || _writeEvent == _null) {
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
    if (_readFile(
          _handle,
          _readBuffer,
          _readBufferSize,
          nullptr,
          _readOverlapped,
        ) ==
        _false) {
      final error = _getLastError();
      if (error == _errorIoPending) return;
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
    if (_writeFile(
          _handle,
          _writeBuffer,
          _writeLength,
          nullptr,
          _writeOverlapped,
        ) ==
        _false) {
      final error = _getLastError();
      if (error == _errorIoPending) return;
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
    if (_handle != _invalidHandleValue) {
      if (!readDone || !writeDone) {
        _cancelIoEx(_handle, nullptr);
        if (!readDone) readDone = _awaitCancel(_readEvent);
        if (!writeDone) writeDone = _awaitCancel(_writeEvent);
      }
      _closeHandle(_handle);
      _handle = _invalidHandleValue;
    }
    // The kernel keeps its own reference to an event, so closing these is
    // safe even if an operation outlived the cancel wait.
    if (_readEvent != _null) _closeHandle(_readEvent);
    if (_writeEvent != _null) _closeHandle(_writeEvent);
    _readEvent = _null;
    _writeEvent = _null;
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

  bool _awaitCancel(int event) =>
      _waitForSingleObject(event, _cancelWaitMs) == _waitObject0;

  void _releaseWriteBuffer() {
    _free(_writeBuffer);
    _writeBuffer = nullptr;
    _writeLength = 0;
  }

  static void _free(Pointer pointer) {
    if (pointer != nullptr) calloc.free(pointer);
  }

  static void _prepare(Pointer<OVERLAPPED> overlapped, int event) {
    final ref = overlapped.ref;
    ref.Internal = 0;
    ref.InternalHigh = 0;
    ref.Offset = 0;
    ref.OffsetHigh = 0;
    ref.hEvent = event;
  }

  /// The event is set only after the kernel has written Internal and
  /// InternalHigh, so it — not Internal — gates reading the result.
  static bool _isSignaled(int event) =>
      _waitForSingleObject(event, 0) == _waitObject0;

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
