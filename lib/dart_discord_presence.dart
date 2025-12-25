/// Dart Discord Presence - Discord Rich Presence for Flutter/Dart desktop applications.
///
/// This package provides Discord Rich Presence functionality for Flutter apps
/// on Windows, macOS, and Linux using pure Dart (no native code required).
///
/// ## Quick Start
///
/// ```dart
/// import 'package:dart_discord_presence/dart_discord_presence.dart';
///
/// void main() async {
///   if (!DiscordRPC.isAvailable) {
///     print('Discord RPC not available on this platform');
///     return;
///   }
///
///   final discord = DiscordRPC();
///
///   discord.onReady.listen((event) {
///     print('Connected as ${event.user.username}');
///   });
///
///   await discord.initialize('YOUR_APPLICATION_ID');
///
///   await discord.setPresence(DiscordPresence(
///     state: 'Playing Solo',
///     details: 'In Main Menu',
///     largeAsset: DiscordAsset(key: 'app_icon', text: 'My App'),
///   ));
/// }
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'src/ipc/discord_ipc_client.dart';
import 'src/models/discord_event.dart';
import 'src/models/discord_presence.dart';
import 'src/models/discord_user.dart';
import 'src/models/enums.dart';

export 'src/exceptions/discord_rpc_exception.dart';
export 'src/models/discord_event.dart';
export 'src/models/discord_presence.dart';
export 'src/models/discord_user.dart';
export 'src/models/enums.dart';

/// Discord Rich Presence client for Flutter/Dart desktop applications.
///
/// Enables desktop applications to display custom status
/// information in Discord user profiles.
class DiscordRPC {
  /// Creates a new Discord RPC instance.
  DiscordRPC();

  final DiscordIpcClient _client = DiscordIpcClient();

  StreamSubscription<DiscordEvent>? _eventSubscription;
  bool _disposed = false;
  bool _initialized = false;

  // Event stream controllers
  final _readyController = StreamController<DiscordReadyEvent>.broadcast();
  final _disconnectedController =
      StreamController<DiscordDisconnectedEvent>.broadcast();
  final _errorController = StreamController<DiscordErrorEvent>.broadcast();
  final _joinGameController =
      StreamController<DiscordJoinGameEvent>.broadcast();
  final _spectateGameController =
      StreamController<DiscordSpectateGameEvent>.broadcast();
  final _joinRequestController =
      StreamController<DiscordJoinRequestEvent>.broadcast();

  // ============================================
  // Platform Availability
  // ============================================

  /// Returns true if Discord RPC is available on the current platform.
  ///
  /// Discord RPC is available on:
  /// - Windows (x64)
  /// - macOS (x64, arm64)
  /// - Linux (x64)
  ///
  /// Returns false on mobile platforms (iOS, Android) and web.
  static bool get isAvailable =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// Returns the list of supported platforms.
  static List<String> get supportedPlatforms => ['windows', 'macos', 'linux'];

  /// Throws [UnsupportedError] if the current platform does not support Discord RPC.
  static void ensureSupported() {
    if (!isAvailable) {
      throw UnsupportedError(
        'Discord RPC is not supported on ${Platform.operatingSystem}. '
        'Supported platforms: ${supportedPlatforms.join(", ")}.',
      );
    }
  }

  // ============================================
  // Event Streams
  // ============================================

  /// Emitted when the connection to Discord is established.
  Stream<DiscordReadyEvent> get onReady => _readyController.stream;

  /// Emitted when the connection to Discord is lost.
  Stream<DiscordDisconnectedEvent> get onDisconnected =>
      _disconnectedController.stream;

  /// Emitted when an error occurs.
  Stream<DiscordErrorEvent> get onError => _errorController.stream;

  /// Emitted when another user clicks "Join" on your presence.
  Stream<DiscordJoinGameEvent> get onJoinGame => _joinGameController.stream;

  /// Emitted when another user clicks "Spectate" on your presence.
  Stream<DiscordSpectateGameEvent> get onSpectateGame =>
      _spectateGameController.stream;

  /// Emitted when another user requests to join your game.
  Stream<DiscordJoinRequestEvent> get onJoinRequest =>
      _joinRequestController.stream;

  /// A combined stream of all Discord RPC events.
  Stream<DiscordEvent> get events => _client.events;

  // ============================================
  // Status
  // ============================================

  /// Returns true if currently connected to Discord.
  bool get isConnected => _client.isConnected;

  /// Returns true if the RPC has been initialized.
  bool get isInitialized => _initialized;

  /// Current connection state.
  DiscordRPCState get connectionState => _client.state;

  // ============================================
  // Lifecycle
  // ============================================

  /// Initialize Discord RPC connection.
  ///
  /// [applicationId] is your Discord application ID from the Developer Portal.
  ///
  /// Throws [UnsupportedError] if platform is not supported.
  /// Throws [DiscordRPCException] if connection fails.
  Future<void> initialize(String applicationId) async {
    ensureSupported();

    if (_disposed) {
      throw StateError('Cannot initialize a disposed DiscordRPC');
    }

    if (_initialized) {
      throw StateError('Already initialized');
    }

    // Set up event routing before connecting
    _eventSubscription = _client.events.listen(_routeEvent);

    try {
      await _client.connect(applicationId);
      _initialized = true;

      // Dispatch the READY event now that _initialized is true
      // This ensures user callbacks can safely call setPresence(), etc.
      _client.dispatchPendingReady();
    } catch (e) {
      // Cleanup on failure
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      await _client.dispose();
      rethrow;
    }
  }

  void _routeEvent(DiscordEvent event) {
    switch (event) {
      case DiscordReadyEvent():
        _readyController.add(event);
      case DiscordDisconnectedEvent():
        _disconnectedController.add(event);
      case DiscordErrorEvent():
        _errorController.add(event);
      case DiscordJoinGameEvent():
        _joinGameController.add(event);
      case DiscordSpectateGameEvent():
        _spectateGameController.add(event);
      case DiscordJoinRequestEvent():
        _joinRequestController.add(event);
    }
  }

  /// Disconnect from Discord and release resources.
  ///
  /// This method is idempotent - calling it multiple times is safe.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _eventSubscription?.cancel();
    _eventSubscription = null;

    await _client.dispose();

    await _readyController.close();
    await _disconnectedController.close();
    await _errorController.close();
    await _joinGameController.close();
    await _spectateGameController.close();
    await _joinRequestController.close();
  }

  /// Alias for [dispose] for API consistency with Discord SDK.
  Future<void> shutdown() => dispose();

  // ============================================
  // Presence Management
  // ============================================

  /// Updates the user's Discord Rich Presence.
  ///
  /// [presence] contains all the data to display in the user's profile.
  ///
  /// Throws [StateError] if not initialized or disposed.
  /// Throws [DiscordRPCException] if the update fails.
  Future<void> setPresence(DiscordPresence presence) async {
    _ensureReady();
    await _client.setPresence(presence);
  }

  /// Clears the current presence.
  ///
  /// Throws [StateError] if not initialized or disposed.
  Future<void> clearPresence() async {
    _ensureReady();
    await _client.clearPresence();
  }

  // ============================================
  // Join Request Handling
  // ============================================

  /// Responds to a join request from another user.
  ///
  /// [userId] is the Discord user ID from the [DiscordJoinRequestEvent].
  /// [reply] specifies whether to accept, deny, or ignore the request.
  Future<void> respondToJoinRequest(
    String userId,
    JoinRequestReply reply,
  ) async {
    _ensureReady();
    await _client.respondToJoinRequest(userId, reply);
  }

  /// Convenience method to accept a join request.
  Future<void> acceptJoinRequest(String userId) =>
      respondToJoinRequest(userId, JoinRequestReply.yes);

  /// Convenience method to deny a join request.
  Future<void> denyJoinRequest(String userId) =>
      respondToJoinRequest(userId, JoinRequestReply.no);

  /// Convenience method to ignore a join request.
  Future<void> ignoreJoinRequest(String userId) =>
      respondToJoinRequest(userId, JoinRequestReply.ignore);

  // ============================================
  // Connected User
  // ============================================

  /// Gets the connected Discord user information.
  ///
  /// Returns null if not connected.
  DiscordUser? get connectedUser => _client.currentUser;

  /// Gets the connected Discord user information.
  ///
  /// Returns null if not connected.
  @Deprecated('Use connectedUser instead')
  DiscordUser? getUser() => connectedUser;

  // ============================================
  // Private Methods
  // ============================================

  void _ensureReady() {
    if (_disposed) {
      throw StateError('DiscordRPC has been disposed');
    }
    if (!_initialized) {
      throw StateError('DiscordRPC has not been initialized');
    }
  }
}
