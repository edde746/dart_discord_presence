/// Base exception for Discord RPC errors.
class DiscordRPCException implements Exception {
  const DiscordRPCException(this.message, [this.code]);

  /// Human-readable error message.
  final String message;

  /// Optional error code from Discord.
  final int? code;

  @override
  String toString() {
    if (code != null) {
      return 'DiscordRPCException($code): $message';
    }
    return 'DiscordRPCException: $message';
  }
}

/// Thrown when Discord is not running or the IPC socket is unavailable.
class DiscordNotRunningException extends DiscordRPCException {
  const DiscordNotRunningException([super.message = 'Discord is not running']);
}

/// Thrown when the connection to Discord fails or is lost.
class DiscordConnectionException extends DiscordRPCException {
  const DiscordConnectionException(super.message, [super.code]);
}

/// Thrown when there's a protocol error (invalid frame, parse error, etc).
class DiscordProtocolException extends DiscordRPCException {
  const DiscordProtocolException(super.message, [super.code]);
}

/// Thrown when an operation is attempted in an invalid state.
class DiscordStateException extends DiscordRPCException {
  const DiscordStateException(super.message);
}
