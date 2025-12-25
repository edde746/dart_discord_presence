import 'dart:async';
import 'dart:typed_data';

import '../exceptions/discord_rpc_exception.dart';
import '../models/discord_event.dart';
import '../models/discord_presence.dart';
import '../models/discord_user.dart';
import '../models/enums.dart';
import '../protocol/command_builder.dart';
import '../protocol/response_parser.dart';
import 'ipc_connection.dart';
import 'ipc_frame.dart';

/// Main Discord IPC client.
///
/// Handles connection lifecycle, message framing, and event delivery.
class DiscordIpcClient {
  IpcConnection? _connection;
  StreamSubscription<IpcFrame>? _frameSubscription;
  Completer<void>? _readyCompleter;

  final _eventController = StreamController<DiscordEvent>.broadcast();

  DiscordRPCState _state = DiscordRPCState.disconnected;
  DiscordUser? _currentUser;
  DiscordReadyEvent? _pendingReadyEvent;

  /// Stream of events from Discord.
  Stream<DiscordEvent> get events => _eventController.stream;

  /// Whether the client is connected to Discord.
  bool get isConnected => _state == DiscordRPCState.connected;

  /// Current connection state.
  DiscordRPCState get state => _state;

  /// The currently connected user, or null if not connected.
  DiscordUser? get currentUser => _currentUser;

  /// Connects to Discord with the given application ID.
  ///
  /// Throws [DiscordNotRunningException] if Discord is not running.
  /// Throws [DiscordStateException] if already connected or connecting.
  Future<void> connect(String applicationId) async {
    if (_state != DiscordRPCState.disconnected) {
      throw const DiscordStateException('Already connected or connecting');
    }

    _readyCompleter = Completer<void>();
    _state = DiscordRPCState.connecting;

    try {
      _connection = IpcConnection();
      await _connection!.open();

      // Listen for incoming frames
      _frameSubscription = _connection!.frames.listen(
        _handleFrame,
        onError: _handleError,
        onDone: _handleDisconnect,
      );

      // Send handshake
      final handshake = CommandBuilder.handshake(applicationId);
      final frame = IpcFrame.fromJson(DiscordOpcode.handshake, handshake);
      await _connection!.sendFrame(frame);

      // Wait for READY event before returning
      await _readyCompleter!.future;

      // Subscribe to activity events after ready (must be sequential, not concurrent)
      await _subscribeToEvents();
    } catch (e) {
      _readyCompleter = null;
      _state = DiscordRPCState.disconnected;
      await _cleanup();
      rethrow;
    }
  }

  void _handleFrame(IpcFrame frame) {
    switch (frame.opcode) {
      case DiscordOpcode.frame:
        _handleJsonFrame(frame);
        break;
      case DiscordOpcode.close:
        _handleDisconnect();
        break;
      case DiscordOpcode.ping:
        _sendPong(frame.payload);
        break;
      case DiscordOpcode.pong:
        // Ignore pong responses
        break;
      case DiscordOpcode.handshake:
        // Shouldn't receive handshake from Discord
        break;
    }
  }

  void _handleJsonFrame(IpcFrame frame) {
    try {
      final json = frame.jsonPayload;
      final event = ResponseParser.parseResponse(json);

      if (event != null) {
        if (event is DiscordReadyEvent) {
          _state = DiscordRPCState.connected;
          _currentUser = event.user;
          _pendingReadyEvent = event; // Store, dispatch later via dispatchPendingReady()
          _readyCompleter?.complete();
          _readyCompleter = null;
          return; // Don't dispatch yet - wait for initialize() to complete
        } else if (event is DiscordErrorEvent &&
            _readyCompleter != null &&
            !_readyCompleter!.isCompleted) {
          // Error during connection handshake
          _readyCompleter!.completeError(
            DiscordConnectionException(event.message, event.errorCode),
          );
          _readyCompleter = null;
        }
        _eventController.add(event);
      }
    } catch (e) {
      // JSON parse error
      _eventController.addError(
        DiscordProtocolException('Failed to parse response: $e'),
      );
    }
  }

  Future<void> _subscribeToEvents() async {
    // Subscribe to activity-related events
    final events = [
      'ACTIVITY_JOIN',
      'ACTIVITY_SPECTATE',
      'ACTIVITY_JOIN_REQUEST',
    ];

    for (final event in events) {
      try {
        final command = CommandBuilder.subscribe(event);
        final frame = IpcFrame.fromJson(DiscordOpcode.frame, command);
        await _connection?.sendFrame(frame);
      } catch (e) {
        // Non-fatal, continue with other subscriptions
      }
    }
  }

  void _handleError(Object error) {
    if (!_eventController.isClosed) {
      _eventController.addError(error);
    }
    disconnect();
  }

  void _handleDisconnect() {
    final wasConnected = _state == DiscordRPCState.connected;
    _state = DiscordRPCState.disconnected;
    _currentUser = null;

    // If we were waiting for READY, signal the error
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(
        const DiscordConnectionException('Connection closed before ready'),
      );
      _readyCompleter = null;
    }

    if (wasConnected && !_eventController.isClosed) {
      _eventController.add(const DiscordDisconnectedEvent(
        errorCode: 0,
        message: 'Connection closed',
      ));
    }
  }

  Future<void> _sendPong(Uint8List payload) async {
    if (_connection?.isOpen != true) return;

    try {
      final frame = IpcFrame(opcode: DiscordOpcode.pong, payload: payload);
      await _connection!.sendFrame(frame);
    } catch (e) {
      // Ignore pong send errors
    }
  }

  /// Updates the presence.
  ///
  /// Throws [DiscordStateException] if not connected.
  Future<void> setPresence(DiscordPresence presence) async {
    _ensureConnected();

    final command = CommandBuilder.setActivity(presence);
    final frame = IpcFrame.fromJson(DiscordOpcode.frame, command);
    await _connection!.sendFrame(frame);
  }

  /// Clears the current presence.
  ///
  /// Throws [DiscordStateException] if not connected.
  Future<void> clearPresence() async {
    _ensureConnected();

    final command = CommandBuilder.setActivity(null);
    final frame = IpcFrame.fromJson(DiscordOpcode.frame, command);
    await _connection!.sendFrame(frame);
  }

  /// Responds to a join request.
  ///
  /// Throws [DiscordStateException] if not connected.
  Future<void> respondToJoinRequest(
    String userId,
    JoinRequestReply reply,
  ) async {
    _ensureConnected();

    final accept = reply == JoinRequestReply.yes;
    final command = CommandBuilder.respondToJoinRequest(userId, accept);
    final frame = IpcFrame.fromJson(DiscordOpcode.frame, command);
    await _connection!.sendFrame(frame);
  }

  /// Disconnects from Discord.
  Future<void> disconnect() async {
    await _cleanup();
    _state = DiscordRPCState.disconnected;
    _currentUser = null;
  }

  Future<void> _cleanup() async {
    await _frameSubscription?.cancel();
    _frameSubscription = null;
    await _connection?.close();
    _connection = null;
  }

  void _ensureConnected() {
    if (_state != DiscordRPCState.connected) {
      throw const DiscordStateException('Not connected to Discord');
    }
  }

  /// Dispatches the pending READY event.
  ///
  /// Call this after initialize() has set _initialized = true,
  /// so that user callbacks can safely use the API.
  void dispatchPendingReady() {
    if (_pendingReadyEvent != null) {
      _eventController.add(_pendingReadyEvent!);
      _pendingReadyEvent = null;
    }
  }

  /// Closes the event controller.
  ///
  /// Call this when disposing of the client.
  Future<void> dispose() async {
    await disconnect();
    await _eventController.close();
  }
}
