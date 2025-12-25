import 'discord_user.dart';

/// Base class for all Discord RPC events.
sealed class DiscordEvent {
  const DiscordEvent();
}

/// Emitted when connection to Discord is established.
class DiscordReadyEvent extends DiscordEvent {
  const DiscordReadyEvent({required this.user});

  /// The connected Discord user.
  final DiscordUser user;

  @override
  String toString() => 'DiscordReadyEvent(user: ${user.username})';
}

/// Emitted when connection to Discord is lost.
class DiscordDisconnectedEvent extends DiscordEvent {
  const DiscordDisconnectedEvent({
    required this.errorCode,
    required this.message,
  });

  /// The error code indicating the reason for disconnection.
  final int errorCode;

  /// Human-readable message describing the disconnection.
  final String message;

  @override
  String toString() => 'DiscordDisconnectedEvent($errorCode: $message)';
}

/// Emitted when an error occurs.
class DiscordErrorEvent extends DiscordEvent {
  const DiscordErrorEvent({
    required this.errorCode,
    required this.message,
  });

  /// The error code.
  final int errorCode;

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'DiscordErrorEvent($errorCode: $message)';
}

/// Emitted when a user clicks "Join" on the presence.
class DiscordJoinGameEvent extends DiscordEvent {
  const DiscordJoinGameEvent({required this.joinSecret});

  /// The join secret configured in the presence.
  final String joinSecret;

  @override
  String toString() => 'DiscordJoinGameEvent(secret: $joinSecret)';
}

/// Emitted when a user clicks "Spectate" on the presence.
class DiscordSpectateGameEvent extends DiscordEvent {
  const DiscordSpectateGameEvent({required this.spectateSecret});

  /// The spectate secret configured in the presence.
  final String spectateSecret;

  @override
  String toString() => 'DiscordSpectateGameEvent(secret: $spectateSecret)';
}

/// Emitted when a user requests to join the game.
class DiscordJoinRequestEvent extends DiscordEvent {
  const DiscordJoinRequestEvent({required this.user});

  /// The user requesting to join.
  final DiscordUser user;

  @override
  String toString() => 'DiscordJoinRequestEvent(user: ${user.username})';
}
