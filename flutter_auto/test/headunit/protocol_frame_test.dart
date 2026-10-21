import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';

void main() {
  group('ProtocolFrame', () {
    test('encodes and decodes a BULK control frame', () {
      final ProtocolFrame original = ProtocolFrame(
        channel: 0,
        frameType: FrameType.bulk,
        messageType: MessageType.control,
        encryptionType: EncryptionType.plain,
        payload: Uint8List.fromList(<int>[0x00, 0x01, 0x00, 0x01]),
      );

      final Uint8List encoded = original.encode();
      final ProtocolFrame decoded = ProtocolFrame.decode(encoded);

      expect(encoded[0], 0);
      expect(encoded[1], 0x07);
      expect(decoded.channel, original.channel);
      expect(decoded.frameType, original.frameType);
      expect(decoded.payload, original.payload);
    });

    test('encodes FIRST frames with an extended header', () {
      final ProtocolFrame frame = ProtocolFrame(
        channel: 0,
        frameType: FrameType.first,
        messageType: MessageType.control,
        encryptionType: EncryptionType.plain,
        payload: Uint8List.fromList(<int>[1, 2, 3]),
        totalMessageSize: 10,
      );

      final Uint8List encoded = frame.encode();
      final ProtocolFrame decoded = ProtocolFrame.decode(encoded);

      expect(encoded.length, 11);
      expect(decoded.headerSize, 8);
      expect(decoded.totalMessageSize, 10);
      expect(decoded.payload, <int>[1, 2, 3]);
    });

    test('rejects incomplete headers', () {
      expect(
        () => ProtocolFrame.decode(Uint8List.fromList(<int>[0, 3, 0])),
        throwsFormatException,
      );
    });

    test('rejects payload length mismatches', () {
      expect(
        () => ProtocolFrame.decode(Uint8List.fromList(<int>[0, 7, 0, 5, 1, 2])),
        throwsFormatException,
      );
    });
  });
}
