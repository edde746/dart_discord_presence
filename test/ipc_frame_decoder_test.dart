import 'dart:typed_data';

import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:dart_discord_presence/src/ipc/ipc_frame.dart';
import 'package:test/test.dart';

Uint8List _frame(DiscordOpcode opcode, String payload) =>
    IpcFrame.fromJson(opcode, {'p': payload}).toBytes();

void main() {
  test('reassembles a frame split inside its header and its payload', () {
    final bytes = _frame(DiscordOpcode.frame, 'hello');
    final decoder = IpcFrameDecoder();

    expect(decoder.add(Uint8List.sublistView(bytes, 0, 3)), isEmpty);
    expect(decoder.add(Uint8List.sublistView(bytes, 3, 12)), isEmpty);
    final frames = decoder.add(Uint8List.sublistView(bytes, 12));

    expect(frames, hasLength(1));
    expect(frames.single.opcode, DiscordOpcode.frame);
    expect(frames.single.jsonPayload, {'p': 'hello'});
  });

  test('returns every frame in a chunk and keeps the trailing partial one', () {
    final first = _frame(DiscordOpcode.frame, 'one');
    final second = _frame(DiscordOpcode.ping, 'two');
    final third = _frame(DiscordOpcode.frame, 'three');
    final chunk = Uint8List.fromList([...first, ...second, ...third.take(5)]);
    final decoder = IpcFrameDecoder();

    final frames = decoder.add(chunk);
    expect(frames.map((f) => f.opcode), [
      DiscordOpcode.frame,
      DiscordOpcode.ping,
    ]);
    expect(frames.map((f) => f.jsonPayload['p']), ['one', 'two']);

    final rest = decoder.add(Uint8List.sublistView(third, 5));
    expect(rest.single.jsonPayload, {'p': 'three'});
  });

  test('rejects an oversized payload as soon as its header arrives', () {
    final header = ByteData(IpcFrame.headerSize)
      ..setUint32(0, DiscordOpcode.frame.value, Endian.little)
      ..setUint32(4, IpcFrame.maxPayloadSize + 1, Endian.little);

    expect(
      () => IpcFrameDecoder().add(header.buffer.asUint8List()),
      throwsA(isA<DiscordProtocolException>()),
    );
  });

  test('rejects an unknown opcode', () {
    final header = ByteData(IpcFrame.headerSize)
      ..setUint32(0, 99, Endian.little)
      ..setUint32(4, 0, Endian.little);

    expect(
      () => IpcFrameDecoder().add(header.buffer.asUint8List()),
      throwsA(isA<DiscordProtocolException>()),
    );
  });
}
