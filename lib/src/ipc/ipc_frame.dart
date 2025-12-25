import 'dart:convert';
import 'dart:typed_data';

/// Discord IPC opcodes for the binary frame protocol.
enum DiscordOpcode {
  /// Initial handshake with client_id and version.
  handshake(0),

  /// Standard JSON message frame.
  frame(1),

  /// Connection close request.
  close(2),

  /// Keep-alive ping.
  ping(3),

  /// Keep-alive pong response.
  pong(4);

  const DiscordOpcode(this.value);

  /// The numeric value sent in the frame header.
  final int value;

  /// Parse an opcode from its numeric value.
  static DiscordOpcode fromValue(int value) {
    return DiscordOpcode.values.firstWhere(
      (op) => op.value == value,
      orElse: () => throw ArgumentError('Unknown opcode: $value'),
    );
  }
}

/// Represents a Discord IPC frame with header and payload.
///
/// Frame format:
/// - Bytes 0-3: Opcode (little-endian uint32)
/// - Bytes 4-7: Payload length (little-endian uint32)
/// - Bytes 8+: JSON payload
class IpcFrame {
  const IpcFrame({required this.opcode, required this.payload});

  /// The frame opcode.
  final DiscordOpcode opcode;

  /// The raw payload bytes.
  final Uint8List payload;

  /// Frame header size in bytes (uint32 opcode + uint32 length).
  static const headerSize = 8;

  /// Maximum payload size (64KB).
  static const maxPayloadSize = 64 * 1024;

  /// Create a frame from a JSON payload.
  factory IpcFrame.fromJson(DiscordOpcode opcode, Map<String, dynamic> json) {
    final jsonString = jsonEncode(json);
    return IpcFrame(
      opcode: opcode,
      payload: Uint8List.fromList(utf8.encode(jsonString)),
    );
  }

  /// Serialize the frame to bytes (header + payload).
  Uint8List toBytes() {
    final totalLength = headerSize + payload.length;
    final buffer = Uint8List(totalLength);
    final byteData = ByteData.sublistView(buffer);

    byteData.setUint32(0, opcode.value, Endian.little);
    byteData.setUint32(4, payload.length, Endian.little);
    buffer.setRange(headerSize, totalLength, payload);

    return buffer;
  }

  /// Parse the payload as JSON.
  Map<String, dynamic> get jsonPayload {
    return jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
  }

  /// Parse frame header from bytes.
  /// Returns null if not enough bytes for a complete header.
  static ({DiscordOpcode opcode, int length})? parseHeader(Uint8List bytes) {
    if (bytes.length < headerSize) return null;

    final byteData = ByteData.sublistView(bytes);
    final opcodeValue = byteData.getUint32(0, Endian.little);
    final length = byteData.getUint32(4, Endian.little);

    return (opcode: DiscordOpcode.fromValue(opcodeValue), length: length);
  }
}
