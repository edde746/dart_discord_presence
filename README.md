# Dart Discord Presence

Discord Rich Presence for Dart desktop applications.

[![Platform Support](https://img.shields.io/badge/platform-windows%20%7C%20macos%20%7C%20linux-blue)](https://github.com/edde746/dart_discord_presence)
[![Dart 3](https://img.shields.io/badge/dart-%3E%3D3.10-blue)](https://dart.dev)

## Features

- **No Flutter dependency** - Works with pure Dart or Flutter desktop apps
- **Event-driven** - Stream-based API for real-time updates
- **Full presence support** - Activity types, timestamps, assets, party info, and secrets
- **Join/Spectate** - Handle game invitations and spectate requests
- **Cross-platform** - Windows (via win32), macOS, and Linux

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dart_discord_presence: ^1.0.0
```

> **Note:** This package only works on desktop platforms. Mobile and web are not supported.

## Quick Start

```dart
import 'package:dart_discord_presence/dart_discord_presence.dart';

void main() async {
  // Check platform support
  if (!DiscordRPC.isAvailable) {
    print('Discord RPC not available on this platform');
    return;
  }

  final discord = DiscordRPC();

  // Listen for connection
  discord.onReady.listen((event) {
    print('Connected as ${event.user.username}');
  });

  // Initialize with your Discord Application ID
  await discord.initialize('YOUR_APPLICATION_ID');

  // Set presence
  await discord.setPresence(DiscordPresence(
    state: 'Playing Solo',
    details: 'In Main Menu',
    largeAsset: DiscordAsset(key: 'app_icon', text: 'My Game'),
  ));

  // Cleanup when done
  await discord.dispose();
}
```

## Platform Support

| Platform | Architecture | Supported |
|----------|-------------|-----------|
| Windows  | x64         | Yes       |
| macOS    | x64, arm64  | Yes       |
| Linux    | x64         | Yes       |
| iOS      | -           | No        |
| Android  | -           | No        |
| Web      | -           | No        |

### macOS Setup

On macOS, the app sandbox blocks access to Discord's IPC socket by default. You need to disable the sandbox for Discord RPC to work.

Edit `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

> **Note:** Disabling the sandbox means your app cannot be distributed on the Mac App Store. For MAS distribution, you would need to use XPC services or other approved IPC mechanisms.

## API Reference

### DiscordRPC

The main class for Discord Rich Presence.

#### Platform Detection

```dart
// Check if Discord RPC is available on current platform
if (DiscordRPC.isAvailable) { ... }

// Get list of supported platform names
List<String> platforms = DiscordRPC.supportedPlatforms;

// Throws UnsupportedError if platform not supported
DiscordRPC.ensureSupported();
```

#### Lifecycle

```dart
final discord = DiscordRPC();

// Initialize connection (required before any operations)
await discord.initialize('APPLICATION_ID');

// Disconnect and release resources
await discord.dispose();
// or
await discord.shutdown(); // Alias for dispose()
```

#### Connection State

```dart
bool connected = discord.isConnected;       // Currently connected?
bool initialized = discord.isInitialized;   // Has initialize() been called?
DiscordRPCState state = discord.connectionState; // disconnected/connecting/connected
DiscordUser? user = discord.connectedUser;  // Connected user info
```

#### Presence Management

```dart
// Update presence
await discord.setPresence(DiscordPresence(
  type: DiscordActivityType.playing,
  state: 'In a match',
  details: 'Ranked - Gold III',
  timestamps: DiscordTimestamps.started(DateTime.now()),
  largeAsset: DiscordAsset(key: 'game_logo'),
  smallAsset: DiscordAsset(key: 'rank_gold'),
));

// Clear presence
await discord.clearPresence();
```

#### Event Streams

All streams are broadcast streams supporting multiple listeners.

```dart
// Connection established
discord.onReady.listen((DiscordReadyEvent event) {
  print('Connected as ${event.user.username}');
});

// Connection lost
discord.onDisconnected.listen((DiscordDisconnectedEvent event) {
  print('Disconnected: ${event.message} (code: ${event.errorCode})');
});

// Error occurred
discord.onError.listen((DiscordErrorEvent event) {
  print('Error: ${event.message} (code: ${event.errorCode})');
});

// User clicked "Join" button
discord.onJoinGame.listen((DiscordJoinGameEvent event) {
  print('Join secret: ${event.joinSecret}');
});

// User clicked "Spectate" button
discord.onSpectateGame.listen((DiscordSpectateGameEvent event) {
  print('Spectate secret: ${event.spectateSecret}');
});

// User requested to join
discord.onJoinRequest.listen((DiscordJoinRequestEvent event) {
  print('${event.user.username} wants to join');
  // Accept, deny, or ignore
  discord.acceptJoinRequest(event.user.userId);
});

// Raw event stream (all events)
discord.events.listen((DiscordEvent event) { ... });
```

#### Join Request Handling

```dart
// Respond with specific reply
await discord.respondToJoinRequest(userId, JoinRequestReply.yes);

// Convenience methods
await discord.acceptJoinRequest(userId);
await discord.denyJoinRequest(userId);
await discord.ignoreJoinRequest(userId);
```

### DiscordPresence

Rich presence configuration.

```dart
DiscordPresence(
  type: DiscordActivityType.playing,  // Activity type
  state: 'In a party',                // Line 2 (max 128 chars)
  details: 'Playing ranked',          // Line 1 (max 128 chars)
  timestamps: DiscordTimestamps(...), // Time display
  largeAsset: DiscordAsset(...),      // Large image
  smallAsset: DiscordAsset(...),      // Small image (corner)
  party: DiscordParty(...),           // Party info
  secrets: DiscordSecrets(...),       // Join/spectate secrets
  instance: true,                     // Instanced activity
)

// Create modified copy
final updated = presence.copyWith(state: 'New state');

// Empty presence (clears all fields)
DiscordPresence.empty()
```

### DiscordActivityType

Determines how the activity appears in Discord.

| Type | Value | Display |
|------|-------|---------|
| `playing` | 0 | "Playing {app name}" |
| `streaming` | 1 | "Streaming {details}" |
| `listening` | 2 | "Listening to {app name}" |
| `watching` | 3 | "Watching {app name}" |
| `competing` | 5 | "Competing in {app name}" |

```dart
DiscordPresence(
  type: DiscordActivityType.listening,
  details: 'Song Title',
  state: 'Artist Name',
)
```

> **Note:** The app name shown in Discord comes from your application name in the Discord Developer Portal, not from code.

### DiscordTimestamps

Controls the time display in the presence.

```dart
// Show elapsed time (counting up)
DiscordTimestamps.started(DateTime.now())

// Show countdown (time remaining)
DiscordTimestamps.ending(DateTime.now().add(Duration(minutes: 5)))

// Show progress bar (for music/media)
// Requires BOTH start and end timestamps
DiscordTimestamps.range(
  DateTime.now(),                                    // Current position
  DateTime.now().add(Duration(minutes: 3, seconds: 30)), // Total duration
)

// Manual timestamps (Unix seconds)
DiscordTimestamps(start: 1234567890, end: 1234567920)
```

**Progress Bar:** When both `start` and `end` are set, Discord displays a progress bar instead of elapsed time. This is ideal for music players, video players, or any timed activity.

### DiscordAsset

Image configuration for presence display.

```dart
// Using Discord Developer Portal asset key
DiscordAsset(key: 'my_asset_key', text: 'Hover tooltip')
DiscordAsset.fromKey('my_asset_key', text: 'Tooltip')

// Using external image URL
DiscordAsset(url: 'https://example.com/image.png', text: 'Tooltip')
DiscordAsset.fromUrl('https://example.com/image.png')
```

Assets must be uploaded in the Discord Developer Portal under your application's Rich Presence settings, or you can use external URLs.

### DiscordParty

Multiplayer party information.

```dart
DiscordParty(
  id: 'unique-party-id',    // Unique identifier
  currentSize: 2,           // Current players
  maxSize: 4,               // Maximum players
  privacy: DiscordPartyPrivacy.public_, // public_ or private_
)
```

### DiscordSecrets

Secrets for join and spectate functionality.

```dart
DiscordSecrets(
  match: 'match-secret',      // Match context
  join: 'join-secret',        // Enables "Join" button
  spectate: 'spectate-secret', // Enables "Spectate" button
)
```

When secrets are set, users viewing your presence can click buttons to join or spectate. Your app receives these through `onJoinGame` and `onSpectateGame` streams.

### DiscordUser

User information received in events.

```dart
String id = user.userId;           // Unique Discord ID
String name = user.username;       // Username
String display = user.displayName; // Global name or username
String? avatar = user.avatar;      // Avatar hash
bool isBot = user.bot;             // Is bot account
int nitro = user.premiumType;      // Nitro subscription type

// Avatar URLs
String? avatarUrl = user.avatarUrl(size: 256);
String defaultUrl = user.defaultAvatarUrl;
String effectiveUrl = user.effectiveAvatarUrl(size: 128);
```

### Exceptions

All exceptions extend `DiscordRPCException`.

```dart
try {
  await discord.initialize('APP_ID');
} on DiscordNotRunningException {
  print('Discord is not running');
} on DiscordConnectionException catch (e) {
  print('Connection failed: ${e.message}');
} on DiscordStateException catch (e) {
  print('Invalid state: ${e.message}');
} on DiscordProtocolException catch (e) {
  print('Protocol error: ${e.message}');
}
```

| Exception | When Thrown |
|-----------|-------------|
| `DiscordNotRunningException` | Discord client is not running |
| `DiscordConnectionException` | Connection failed or lost |
| `DiscordStateException` | Operation in invalid state (not initialized, already disposed) |
| `DiscordProtocolException` | Protocol error (invalid frame, parse error) |

## Advanced Examples

### Music Player with Progress Bar

```dart
void updateNowPlaying(Track track, Duration position) async {
  final now = DateTime.now();
  final start = now.subtract(position);
  final end = now.add(track.duration - position);

  await discord.setPresence(DiscordPresence(
    type: DiscordActivityType.listening,
    details: track.title,
    state: track.artist,
    timestamps: DiscordTimestamps.range(start, end),
    largeAsset: DiscordAsset(
      url: track.albumArtUrl,
      text: track.album,
    ),
  ));
}
```

### Multiplayer Game with Party

```dart
await discord.setPresence(DiscordPresence(
  type: DiscordActivityType.playing,
  state: 'In a Party',
  details: 'Competitive Match',
  party: DiscordParty(
    id: gameSession.partyId,
    currentSize: gameSession.players.length,
    maxSize: 4,
    privacy: DiscordPartyPrivacy.public_,
  ),
  secrets: DiscordSecrets(
    join: gameSession.joinCode,
  ),
  largeAsset: DiscordAsset(key: 'game_logo'),
));

// Handle join requests
discord.onJoinGame.listen((event) {
  final joinCode = event.joinSecret;
  gameSession.joinWithCode(joinCode);
});
```

### Error Handling

```dart
final discord = DiscordRPC();

discord.onError.listen((event) {
  log('Discord RPC error: ${event.message}');
});

discord.onDisconnected.listen((event) {
  log('Disconnected from Discord');
  // Optionally attempt reconnection
  _scheduleReconnect();
});

try {
  await discord.initialize('APP_ID');
} on DiscordNotRunningException {
  // Discord not running - presence won't work, but app continues
  log('Discord not detected, Rich Presence disabled');
} on DiscordConnectionException catch (e) {
  log('Failed to connect: ${e.message}');
}
```

## Discord Developer Portal Setup

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **New Application** and give it a name
3. Copy your **Application ID** - this is what you pass to `initialize()`
4. Under **Rich Presence > Art Assets**, upload images for your presence
5. Use the asset names as `key` values in `DiscordAsset`

## Troubleshooting

### "Discord is not running"

Make sure the Discord desktop app is running. Discord RPC communicates with the local Discord client via IPC.

### "Platform not supported"

This package only works on Windows, macOS, and Linux. Check `DiscordRPC.isAvailable` before initializing.

### Connection fails on macOS

The macOS app sandbox blocks access to Discord's IPC socket. See [macOS Setup](#macos-setup) to disable the sandbox.

### Progress bar not showing

The progress bar requires **both** `start` and `end` timestamps. If only `start` is set, Discord shows elapsed time instead.

```dart
// This shows elapsed time (no progress bar)
DiscordTimestamps.started(DateTime.now())

// This shows a progress bar
DiscordTimestamps.range(startTime, endTime)
```

### Presence not updating

- Ensure `initialize()` completed successfully
- Check `isConnected` before calling `setPresence()`
- Listen to `onError` for any errors

