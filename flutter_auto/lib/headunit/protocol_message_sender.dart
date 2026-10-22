
import 'dart:typed_data';

import 'package:flutter_auto/headunit/protocol_connection.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';

typedef ApplicationEncryptor = Future<Uint8List> Function(
  Uint8List payload,
);

class ProtocolMessageSender {
  ProtocolMessageSender(this.connection);

  final ProtocolConnection connection;
  ApplicationEncryptor? _encryptor;

  void setApplicationEncryptor(ApplicationEncryptor encryptor) {
    _encryptor = encryptor;
  }

  void clearApplicationEncryptor() {
    _encryptor = null;
  }

  Future<void> send({
    required int channelId,
    required int messageId,
    required Uint8List body,
    required EncryptionType encryptionType,
    MessageType messageType = MessageType.specific,
    FrameType frameType = FrameType.bulk,
  }) async {
    if (messageId < 0 || messageId > 0xFFFF) {
      throw RangeError.range(messageId, 0, 0xFFFF, 'messageId');
    }

    if (connection.isClosed) {
      throw StateError('Cannot send on a closed protocol connection.');
    }

    // Prefix the message ID to the protobuf or TLS body.
    final payload = Uint8List(2 + body.length);
    ByteData.sublistView(payload).setUint16(
      0,
      messageId,
      Endian.big,
    );
    payload.setRange(2, payload.length, body);

    final Uint8List wirePayload;

    if (encryptionType == EncryptionType.encrypted) {
      final encryptor = _encryptor;
      if (encryptor == null) {
        throw StateError(
          'Cannot encrypt a message before TLS is ready.',
        );
      }

      wirePayload = await encryptor(payload);
    } else {
      wirePayload = payload;
    }

    await connection.send(
      ProtocolFrame(
        channel: channelId,
        frameType: frameType,
        messageType: messageType,
        encryptionType: encryptionType,
        payload: wirePayload,
      ),
    );
  }
}
