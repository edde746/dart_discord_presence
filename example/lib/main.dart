import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dart_discord_presence/dart_discord_presence.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Discord RPC Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5865F2), // Discord Blurple
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const DiscordRPCDemo(),
    );
  }
}

class DiscordRPCDemo extends StatefulWidget {
  const DiscordRPCDemo({super.key});

  @override
  State<DiscordRPCDemo> createState() => _DiscordRPCDemoState();
}

class _DiscordRPCDemoState extends State<DiscordRPCDemo> {
  // Get one from: https://discord.com/developers/applications
  static const applicationId = '1453040400578379913'; // Test App ID, don't use in production

  DiscordRPC? _discord;
  final List<StreamSubscription> _subscriptions = [];

  bool _isSupported = false;
  bool _isConnected = false;
  DiscordUser? _user;
  String _status = 'Not initialized';
  final List<String> _logs = [];

  final _stateController = TextEditingController(text: 'Playing Flutter Demo');
  final _detailsController = TextEditingController(text: 'In Main Menu');
  final _largeImageController = TextEditingController(text: 'flutter_logo');
  final _largeTextController = TextEditingController(text: 'Flutter');
  DiscordActivityType _selectedActivityType = DiscordActivityType.playing;

  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  void _checkSupport() {
    _isSupported = DiscordRPC.isAvailable;
    if (!_isSupported) {
      _addLog('Discord RPC not supported on this platform');
      _addLog('Supported: ${DiscordRPC.supportedPlatforms.join(", ")}');
    } else {
      _addLog('Discord RPC is supported');
    }
    setState(() {});
  }

  Future<void> _initialize() async {
    if (!_isSupported) return;

    try {
      _discord = DiscordRPC();

      // Set up event listeners
      _subscriptions.add(_discord!.onReady.listen((event) {
        _addLog('Connected as ${event.user.username}');
        setState(() {
          _isConnected = true;
          _user = event.user;
          _status = 'Connected';
        });
        // Auto-set initial presence on connection
        _updatePresence();
      }));

      _subscriptions.add(_discord!.onDisconnected.listen((event) {
        _addLog('Disconnected: ${event.message}');
        setState(() {
          _isConnected = false;
          _user = null;
          _status = 'Disconnected';
        });
      }));

      _subscriptions.add(_discord!.onError.listen((event) {
        _addLog('Error: ${event.message}');
      }));

      _subscriptions.add(_discord!.onJoinGame.listen((event) {
        _addLog('Join game requested: ${event.joinSecret}');
      }));

      _subscriptions.add(_discord!.onJoinRequest.listen((event) {
        _addLog('Join request from ${event.user.username}');
        _showJoinRequestDialog(event.user);
      }));

      // Initialize
      setState(() => _status = 'Initializing...');
      await _discord!.initialize(applicationId);
      _addLog('Initialized with app ID: $applicationId');
      setState(() => _status = 'Waiting for connection...');
    } catch (e) {
      _addLog('Error: $e');
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _shutdown() async {
    if (_discord == null) return;

    try {
      for (final sub in _subscriptions) {
        await sub.cancel();
      }
      _subscriptions.clear();

      await _discord!.dispose();
      _discord = null;

      _addLog('Shutdown complete');
      if (mounted) {
        setState(() {
          _isConnected = false;
          _user = null;
          _status = 'Shutdown';
        });
      }
    } catch (e) {
      _addLog('Shutdown error: $e');
    }
  }

  Future<void> _updatePresence() async {
    if (_discord == null || !_isConnected) return;

    try {
      await _discord!.setPresence(DiscordPresence(
        type: _selectedActivityType,
        state: _stateController.text,
        details: _detailsController.text,
        timestamps: DiscordTimestamps.started(DateTime.now()),
        largeAsset: _largeImageController.text.isNotEmpty
            ? DiscordAsset(
                key: _largeImageController.text,
                text: _largeTextController.text,
              )
            : null,
      ));
      _addLog('Presence updated (${_selectedActivityType.name})');
    } catch (e) {
      _addLog('Update presence error: $e');
    }
  }

  Future<void> _clearPresence() async {
    if (_discord == null || !_isConnected) return;

    try {
      await _discord!.clearPresence();
      _addLog('Presence cleared');
    } catch (e) {
      _addLog('Clear presence error: $e');
    }
  }

  void _showJoinRequestDialog(DiscordUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Request'),
        content: Text('${user.username} wants to join your game'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _discord?.denyJoinRequest(user.userId);
              _addLog('Denied join request from ${user.username}');
            },
            child: const Text('Deny'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _discord?.acceptJoinRequest(user.userId);
              _addLog('Accepted join request from ${user.username}');
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    if (!mounted) return;
    setState(() {
      _logs.insert(0, '[$timestamp] $message');
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  @override
  void dispose() {
    _shutdown();
    _stateController.dispose();
    _detailsController.dispose();
    _largeImageController.dispose();
    _largeTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Discord RPC Demo'),
        actions: [
          if (_user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  'Connected: ${_user!.username}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Controls
            Expanded(
              flex: 1,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Status: $_status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),

                      // Connection buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed:
                                  _isSupported && _discord == null ? _initialize : null,
                              child: const Text('Initialize'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _discord != null ? _shutdown : null,
                              child: const Text('Shutdown'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Presence fields
                      const Text('Rich Presence Settings',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<DiscordActivityType>(
                        initialValue: _selectedActivityType,
                        decoration: const InputDecoration(
                          labelText: 'Activity Type',
                          border: OutlineInputBorder(),
                        ),
                        items: DiscordActivityType.values.map((type) {
                          final names = {
                            DiscordActivityType.playing: 'Playing',
                            DiscordActivityType.streaming: 'Streaming',
                            DiscordActivityType.listening: 'Listening',
                            DiscordActivityType.watching: 'Watching',
                            DiscordActivityType.competing: 'Competing',
                          };
                          return DropdownMenuItem(
                            value: type,
                            child: Text(names[type] ?? type.name),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedActivityType = value);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _stateController,
                        decoration: const InputDecoration(
                          labelText: 'State',
                          hintText: 'e.g., Playing Solo',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _detailsController,
                        decoration: const InputDecoration(
                          labelText: 'Details',
                          hintText: 'e.g., In Main Menu',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _largeImageController,
                        decoration: const InputDecoration(
                          labelText: 'Large Image Key',
                          hintText: 'Asset key from Discord Dev Portal',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _largeTextController,
                        decoration: const InputDecoration(
                          labelText: 'Large Image Text',
                          hintText: 'Tooltip text',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Presence buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isConnected ? _updatePresence : null,
                              child: const Text('Update Presence'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isConnected ? _clearPresence : null,
                              child: const Text('Clear'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Logs
            Expanded(
              flex: 1,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Event Log',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          TextButton(
                            onPressed: () => setState(() => _logs.clear()),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                _logs[index],
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
