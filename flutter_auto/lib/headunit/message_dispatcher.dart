import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_auto/headunit/protocol_frame.dart';

import 'protocol_message.dart';

class DispatchedMessage {
  const DispatchedMessage({
    required this.channel,
    required this.messageId,
    required this.messageType,
    required this.encryptionType,
    required this.payload,
  });

  final int channel;
  final int messageId;
  final MessageType messageType;
  final EncryptionType encryptionType;

  /// Message body after the two-byte message ID.
  final Uint8List payload;
}

class MessageDispatcher {
  const MessageDispatcher();

  Stream<DispatchedMessage> bind(Stream<ProtocolMessage> messages) async* {
    await for (final ProtocolMessage message in messages) {
      if (message.payload.length < 2) {
        throw FormatException(
          'Message on channel ${message.channel} is too short '
          'to contain a two-byte message ID.',
        );
      }

      final ByteData data = ByteData.sublistView(message.payload);

      final int messageId = data.getUint16(0, Endian.big);

      final Uint8List payload = Uint8List.fromList(message.payload.sublist(2));

      yield DispatchedMessage(
        channel: message.channel,
        messageId: messageId,
        messageType: message.messageType,
        encryptionType: message.encryptionType,
        payload: payload,
      );
    }
  }
}
