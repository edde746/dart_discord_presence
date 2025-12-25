import '../models/discord_event.dart';
import '../models/discord_user.dart';

/// Parses JSON responses from the Discord IPC.
class ResponseParser {
  /// Parses a response/event from Discord.
  ///
  /// Returns null if the response doesn't contain a recognized event.
  static DiscordEvent? parseResponse(Map<String, dynamic> json) {
    final evt = json['evt'] as String?;
    final data = json['data'] as Map<String, dynamic>?;
    final cmd = json['cmd'] as String?;

    // Check for error in response to a command
    if (evt == 'ERROR' || (data != null && data.containsKey('code'))) {
      final errorData = data ?? json;
      return DiscordErrorEvent(
        errorCode: errorData['code'] as int? ?? 0,
        message: errorData['message'] as String? ?? 'Unknown error',
      );
    }

    // Handle events
    if (evt != null) {
      return _parseEvent(evt, data);
    }

    // Handle command responses (e.g., DISPATCH for READY)
    if (cmd == 'DISPATCH' && data != null) {
      final eventType = data['evt'] as String?;
      if (eventType != null) {
        return _parseEvent(eventType, data['data'] as Map<String, dynamic>?);
      }
    }

    return null;
  }

  static DiscordEvent? _parseEvent(String evt, Map<String, dynamic>? data) {
    switch (evt) {
      case 'READY':
        final userData = data?['user'] as Map<String, dynamic>?;
        if (userData != null) {
          return DiscordReadyEvent(user: _parseUser(userData));
        }
        return null;

      case 'ERROR':
        return DiscordErrorEvent(
          errorCode: data?['code'] as int? ?? 0,
          message: data?['message'] as String? ?? 'Unknown error',
        );

      case 'ACTIVITY_JOIN':
        final secret = data?['secret'] as String?;
        if (secret != null) {
          return DiscordJoinGameEvent(joinSecret: secret);
        }
        return null;

      case 'ACTIVITY_SPECTATE':
        final secret = data?['secret'] as String?;
        if (secret != null) {
          return DiscordSpectateGameEvent(spectateSecret: secret);
        }
        return null;

      case 'ACTIVITY_JOIN_REQUEST':
        final userData = data?['user'] as Map<String, dynamic>?;
        if (userData != null) {
          return DiscordJoinRequestEvent(user: _parseUser(userData));
        }
        return null;

      default:
        return null;
    }
  }

  /// Parses a user object from Discord's JSON format.
  static DiscordUser _parseUser(Map<String, dynamic> json) {
    return DiscordUser(
      userId: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      discriminator: json['discriminator'] as String? ?? '0',
      globalName: json['global_name'] as String?,
      avatar: json['avatar'] as String?,
      bot: json['bot'] as bool? ?? false,
      premiumType: json['premium_type'] as int? ?? 0,
    );
  }
}
