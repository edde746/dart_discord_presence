/// Represents a Discord user.
///
/// Received in ready events and join request events.
class DiscordUser {
  /// Creates a Discord user instance.
  const DiscordUser({
    required this.userId,
    required this.username,
    this.discriminator = '0',
    this.globalName,
    this.avatar,
    this.bot = false,
    this.premiumType = 0,
  });

  /// The user's unique Discord ID.
  final String userId;

  /// The user's username.
  final String username;

  /// The user's discriminator (legacy, usually "0" for new usernames).
  final String discriminator;

  /// The user's display name (global name).
  final String? globalName;

  /// The user's avatar hash, or null for default avatar.
  final String? avatar;

  /// Whether the user is a bot account.
  final bool bot;

  /// Type of Nitro subscription.
  final int premiumType;

  /// Returns the display name (global name if set, otherwise username).
  String get displayName => globalName?.isNotEmpty == true ? globalName! : username;

  /// Returns the URL for the user's avatar.
  ///
  /// [size] can be 16, 32, 64, 128, 256, 512, or 1024.
  String? avatarUrl({int size = 128}) {
    if (avatar == null || avatar!.isEmpty) return null;
    final ext = avatar!.startsWith('a_') ? 'gif' : 'png';
    return 'https://cdn.discordapp.com/avatars/$userId/$avatar.$ext?size=$size';
  }

  /// Returns the default avatar URL if no custom avatar is set.
  String get defaultAvatarUrl {
    final id = int.tryParse(userId) ?? 0;
    final index = (id >> 22) % 6;
    return 'https://cdn.discordapp.com/embed/avatars/$index.png';
  }

  /// Returns the effective avatar URL (custom or default).
  String effectiveAvatarUrl({int size = 128}) {
    return avatarUrl(size: size) ?? defaultAvatarUrl;
  }

  @override
  String toString() => 'DiscordUser($username#$discriminator)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscordUser &&
          runtimeType == other.runtimeType &&
          userId == other.userId;

  @override
  int get hashCode => userId.hashCode;
}
