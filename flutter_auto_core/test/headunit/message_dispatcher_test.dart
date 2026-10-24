import 'dart:typed_data';

import 'package:flutter_auto_core/flutter_auto_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageDispatcher', () {
    const MessageDispatcher dispatcher = MessageDispatcher();

    ProtocolMessage createMessage({
      required int channel,
      required List<int> payload,
    }) {
      return ProtocolMessage(
        channel: channel,
        messageType: channel == 0 ? MessageType.control : MessageType.specific,
        encryptionType: EncryptionType.plain,
        payload: Uint8List.fromList(payload),
      );
    }

    test('extracts a big-endian message ID and body', () async {
      final ProtocolMessage message = createMessage(
        channel: 0,
        payload: <int>[0x00, 0x01, 0x00, 0x01, 0x00, 0x01],
      );

      final List<DispatchedMessage> results = await dispatcher
          .bind(Stream<ProtocolMessage>.value(message))
          .toList();

      expect(results, hasLength(1));
      expect(results.single.channel, 0);
      expect(results.single.messageId, 1);
      expect(results.single.payload, equals(<int>[0x00, 0x01, 0x00, 0x01]));
    });

    test('supports message IDs greater than 255', () async {
      final ProtocolMessage message = createMessage(
        channel: 1,
        payload: <int>[0x80, 0x01, 0xAA, 0xBB],
      );

      final List<DispatchedMessage> results = await dispatcher
          .bind(Stream<ProtocolMessage>.value(message))
          .toList();

      expect(results.single.messageId, 0x8001);
      expect(results.single.payload, equals(<int>[0xAA, 0xBB]));
    });

    test('preserves channel and metadata', () async {
      final ProtocolMessage message = ProtocolMessage(
        channel: 3,
        messageType: MessageType.specific,
        encryptionType: EncryptionType.encrypted,
        payload: Uint8List.fromList(<int>[0x80, 0x01, 0x55]),
      );

      final List<DispatchedMessage> results = await dispatcher
          .bind(Stream<ProtocolMessage>.value(message))
          .toList();

      expect(results.single.channel, 3);
      expect(results.single.messageType, MessageType.specific);
      expect(results.single.encryptionType, EncryptionType.encrypted);
      expect(results.single.payload, equals(<int>[0x55]));
    });

    test('rejects a message with no message ID', () async {
      final ProtocolMessage message = createMessage(
        channel: 0,
        payload: <int>[0x01],
      );

      await expectLater(
        dispatcher.bind(Stream<ProtocolMessage>.value(message)).toList(),
        throwsFormatException,
      );
    });

    test('accepts a message with an empty body', () async {
      final ProtocolMessage message = createMessage(
        channel: 0,
        payload: <int>[0x00, 0x01],
      );

      final List<DispatchedMessage> results = await dispatcher
          .bind(Stream<ProtocolMessage>.value(message))
          .toList();

      expect(results.single.messageId, 1);
      expect(results.single.payload, isEmpty);
    });
  });
}
