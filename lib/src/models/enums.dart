/// Reply options for join requests.
enum JoinRequestReply {
  /// Deny the join request.
  no(0),

  /// Accept the join request.
  yes(1),

  /// Ignore/timeout the request.
  ignore(2);

  const JoinRequestReply(this.value);

  /// The native value passed to the Discord SDK.
  final int value;
}

/// Connection state of the Discord RPC client.
enum DiscordRPCState {
  /// Not connected and not attempting to connect.
  disconnected,

  /// Currently attempting to connect to Discord.
  connecting,

  /// Connected to Discord and ready to send/receive data.
  connected,
}
