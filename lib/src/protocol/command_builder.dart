import 'dart:io';

import '../models/discord_presence.dart';

/// Builds JSON commands for the Discord IPC protocol.
class CommandBuilder {
  static int _nonceCounter = 0;

  static String _generateNonce() => '${++_nonceCounter}';

  /// Builds the initial handshake message.
  ///
  /// Sent with opcode HANDSHAKE (0) when first connecting.
  static Map<String, dynamic> handshake(String clientId) {
    return {
      'v': 1,
      'client_id': clientId,
    };
  }

  /// Builds a SET_ACTIVITY command to update presence.
  ///
  /// Pass null for [presence] to clear the current activity.
  static Map<String, dynamic> setActivity(DiscordPresence? presence) {
    final args = <String, dynamic>{
      'pid': pid,
    };

    if (presence != null) {
      final activity = <String, dynamic>{
        'type': presence.type.value,
      };

      if (presence.state != null) {
        activity['state'] = presence.state;
      }
      if (presence.details != null) {
        activity['details'] = presence.details;
      }

      // Timestamps
      if (presence.timestamps != null) {
        final timestamps = <String, dynamic>{};
        if (presence.timestamps!.start != null) {
          timestamps['start'] = presence.timestamps!.start;
        }
        if (presence.timestamps!.end != null) {
          timestamps['end'] = presence.timestamps!.end;
        }
        if (timestamps.isNotEmpty) {
          activity['timestamps'] = timestamps;
        }
      }

      // Assets
      final assets = <String, dynamic>{};
      if (presence.largeAsset != null) {
        assets['large_image'] = presence.largeAsset!.effectiveKey;
        if (presence.largeAsset!.text != null) {
          assets['large_text'] = presence.largeAsset!.text;
        }
      }
      if (presence.smallAsset != null) {
        assets['small_image'] = presence.smallAsset!.effectiveKey;
        if (presence.smallAsset!.text != null) {
          assets['small_text'] = presence.smallAsset!.text;
        }
      }
      if (assets.isNotEmpty) {
        activity['assets'] = assets;
      }

      // Party
      if (presence.party != null) {
        final party = <String, dynamic>{
          'id': presence.party!.id,
          'size': [presence.party!.currentSize, presence.party!.maxSize],
        };
        if (presence.party!.privacy.value != 0) {
          party['privacy'] = presence.party!.privacy.value;
        }
        activity['party'] = party;
      }

      // Secrets
      if (presence.secrets != null) {
        final secrets = <String, dynamic>{};
        if (presence.secrets!.match != null) {
          secrets['match'] = presence.secrets!.match;
        }
        if (presence.secrets!.join != null) {
          secrets['join'] = presence.secrets!.join;
        }
        if (presence.secrets!.spectate != null) {
          secrets['spectate'] = presence.secrets!.spectate;
        }
        if (secrets.isNotEmpty) {
          activity['secrets'] = secrets;
        }
      }

      if (presence.instance == true) {
        activity['instance'] = true;
      }

      args['activity'] = activity;
    }

    return {
      'nonce': _generateNonce(),
      'cmd': 'SET_ACTIVITY',
      'args': args,
    };
  }

  /// Builds a response to a join request.
  ///
  /// Set [accept] to true to send SEND_ACTIVITY_JOIN_INVITE,
  /// or false to send CLOSE_ACTIVITY_REQUEST.
  static Map<String, dynamic> respondToJoinRequest(
    String userId,
    bool accept,
  ) {
    return {
      'nonce': _generateNonce(),
      'cmd': accept ? 'SEND_ACTIVITY_JOIN_INVITE' : 'CLOSE_ACTIVITY_REQUEST',
      'args': {
        'user_id': userId,
      },
    };
  }

  /// Builds a SUBSCRIBE command for activity events.
  static Map<String, dynamic> subscribe(String event) {
    return {
      'nonce': _generateNonce(),
      'cmd': 'SUBSCRIBE',
      'evt': event,
    };
  }
}
