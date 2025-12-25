import 'dart:async';
import 'dart:io';

import 'ipc_frame.dart';
import 'unix_socket_connection.dart';
import 'windows_pipe_connection.dart';

/// Abstract interface for platform-specific Discord IPC connections.
///
/// Discord uses different IPC mechanisms on each platform:
/// - macOS/Linux: Unix domain sockets
/// - Windows: Named pipes
abstract class IpcConnection {
  /// Opens a connection to Discord's IPC socket/pipe.
  ///
  /// Automatically tries socket indices 0-9 until one succeeds.
  /// Throws [DiscordNotRunningException] if no connection can be made.
  Future<void> open();

  /// Closes the connection.
  Future<void> close();

  /// Whether the connection is currently open.
  bool get isOpen;

  /// Stream of incoming frames from Discord.
  Stream<IpcFrame> get frames;

  /// Sends a frame to Discord.
  Future<void> sendFrame(IpcFrame frame);

  /// Creates a platform-appropriate connection implementation.
  factory IpcConnection() {
    if (Platform.isWindows) {
      return WindowsPipeConnection();
    } else if (Platform.isMacOS || Platform.isLinux) {
      return UnixSocketConnection();
    }
    throw UnsupportedError(
      'Discord RPC is not supported on ${Platform.operatingSystem}',
    );
  }
}
