/// Discord activity types that determine how the presence is displayed.
enum DiscordActivityType {
  /// "Playing {name}" - Default for games
  playing(0),

  /// "Streaming {details}" - Shows as streaming (purple)
  streaming(1),

  /// "Listening to {name}" - For music/audio apps
  listening(2),

  /// "Watching {name}" - For video/media apps
  watching(3),

  /// "Competing in {name}" - For competitive activities
  competing(5);

  const DiscordActivityType(this.value);

  /// The integer value sent to Discord's API.
  final int value;
}

/// Controls which field is displayed in the user's status text in the member list.
enum DiscordStatusDisplayType {
  /// Shows the app name (default) - e.g., "Listening to Spotify"
  name(0),

  /// Shows the state field - e.g., "Listening to Rick Astley"
  state(1),

  /// Shows the details field - e.g., "Listening to Never Gonna Give You Up"
  details(2);

  const DiscordStatusDisplayType(this.value);

  /// The integer value sent to Discord's API.
  final int value;
}

/// Timestamp configuration for presence display.
class DiscordTimestamps {
  /// Creates timestamps with explicit Unix second values.
  const DiscordTimestamps({
    this.start,
    this.end,
  });

  /// Creates a timestamp showing elapsed time from [startTime].
  factory DiscordTimestamps.started(DateTime startTime) {
    return DiscordTimestamps(
      start: startTime.millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Creates a timestamp showing countdown to [endTime].
  factory DiscordTimestamps.ending(DateTime endTime) {
    return DiscordTimestamps(
      end: endTime.millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Creates a timestamp showing both elapsed and remaining time.
  factory DiscordTimestamps.range(DateTime startTime, DateTime endTime) {
    return DiscordTimestamps(
      start: startTime.millisecondsSinceEpoch ~/ 1000,
      end: endTime.millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Activity start time as Unix timestamp in seconds.
  final int? start;

  /// Activity end time as Unix timestamp in seconds.
  final int? end;

  DiscordTimestamps copyWith({int? start, int? end}) {
    return DiscordTimestamps(
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

/// Image asset configuration for presence display.
class DiscordAsset {
  /// Creates an asset configuration with an asset key.
  const DiscordAsset({
    this.key,
    this.url,
    this.text,
  }) : assert(key != null || url != null, 'Either key or url must be provided');

  /// Creates an asset from a Discord Developer Portal asset key.
  const DiscordAsset.fromKey(this.key, {this.text}) : url = null;

  /// Creates an asset from an external image URL.
  const DiscordAsset.fromUrl(this.url, {this.text}) : key = null;

  /// The asset key as configured in Discord Developer Portal.
  final String? key;

  /// External image URL (Discord accepts URLs directly).
  final String? url;

  /// Tooltip text displayed on hover.
  final String? text;

  /// Returns the effective key to send to Discord (key takes precedence over url).
  String get effectiveKey => key ?? url!;

  DiscordAsset copyWith({String? key, String? url, String? text}) {
    return DiscordAsset(
      key: key ?? this.key,
      url: url ?? this.url,
      text: text ?? this.text,
    );
  }
}

/// Party configuration for multiplayer presence.
class DiscordParty {
  /// Creates a party configuration.
  const DiscordParty({
    required this.id,
    required this.currentSize,
    required this.maxSize,
    this.privacy = DiscordPartyPrivacy.private_,
  });

  /// Unique party identifier.
  final String id;

  /// Current number of players in the party.
  final int currentSize;

  /// Maximum capacity of the party.
  final int maxSize;

  /// Party privacy setting.
  final DiscordPartyPrivacy privacy;

  DiscordParty copyWith({
    String? id,
    int? currentSize,
    int? maxSize,
    DiscordPartyPrivacy? privacy,
  }) {
    return DiscordParty(
      id: id ?? this.id,
      currentSize: currentSize ?? this.currentSize,
      maxSize: maxSize ?? this.maxSize,
      privacy: privacy ?? this.privacy,
    );
  }
}

/// Party privacy settings.
enum DiscordPartyPrivacy {
  /// Private party.
  private_(0),

  /// Public party.
  public_(1);

  const DiscordPartyPrivacy(this.value);

  final int value;
}

/// Secrets for join/spectate functionality.
class DiscordSecrets {
  /// Creates a secrets configuration.
  const DiscordSecrets({
    this.match,
    this.join,
    this.spectate,
  });

  /// Match secret for match context.
  final String? match;

  /// Secret for joining the game.
  final String? join;

  /// Secret for spectating the game.
  final String? spectate;

  DiscordSecrets copyWith({
    String? match,
    String? join,
    String? spectate,
  }) {
    return DiscordSecrets(
      match: match ?? this.match,
      join: join ?? this.join,
      spectate: spectate ?? this.spectate,
    );
  }
}

/// Represents Discord Rich Presence data.
class DiscordPresence {
  /// Creates a new presence configuration.
  const DiscordPresence({
    this.type = DiscordActivityType.playing,
    this.state,
    this.details,
    this.timestamps,
    this.largeAsset,
    this.smallAsset,
    this.party,
    this.secrets,
    this.instance,
    this.statusDisplayType,
  });

  /// Creates an empty presence (clears all fields).
  const DiscordPresence.empty()
      : type = DiscordActivityType.playing,
        state = null,
        details = null,
        timestamps = null,
        largeAsset = null,
        smallAsset = null,
        party = null,
        secrets = null,
        instance = null,
        statusDisplayType = null;

  /// The activity type (playing, listening, watching, etc.).
  final DiscordActivityType type;

  /// The player's current party status (max 128 chars).
  final String? state;

  /// What the player is currently doing (max 128 chars).
  final String? details;

  /// Timestamps for elapsed/remaining time display.
  final DiscordTimestamps? timestamps;

  /// The large (primary) image displayed in the presence.
  final DiscordAsset? largeAsset;

  /// The small (secondary) image displayed in the presence.
  final DiscordAsset? smallAsset;

  /// Party information for multiplayer games.
  final DiscordParty? party;

  /// Secrets for join/spectate functionality.
  final DiscordSecrets? secrets;

  /// Whether this activity is an instanced context.
  final bool? instance;

  /// Controls which field is displayed in the member list status text.
  final DiscordStatusDisplayType? statusDisplayType;

  /// Creates a copy with modified fields.
  DiscordPresence copyWith({
    DiscordActivityType? type,
    String? state,
    String? details,
    DiscordTimestamps? timestamps,
    DiscordAsset? largeAsset,
    DiscordAsset? smallAsset,
    DiscordParty? party,
    DiscordSecrets? secrets,
    bool? instance,
    DiscordStatusDisplayType? statusDisplayType,
  }) {
    return DiscordPresence(
      type: type ?? this.type,
      state: state ?? this.state,
      details: details ?? this.details,
      timestamps: timestamps ?? this.timestamps,
      largeAsset: largeAsset ?? this.largeAsset,
      smallAsset: smallAsset ?? this.smallAsset,
      party: party ?? this.party,
      secrets: secrets ?? this.secrets,
      instance: instance ?? this.instance,
      statusDisplayType: statusDisplayType ?? this.statusDisplayType,
    );
  }

  @override
  String toString() => 'DiscordPresence(state: $state, details: $details)';
}
