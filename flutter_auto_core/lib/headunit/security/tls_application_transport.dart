import 'dart:typed_data';

import '../protocol_connection.dart';
import '../protocol_frame.dart';
import 'android_auto_tls_client.dart';

class TlsApplicationTransport {
  TlsApplicationTransport({required this.connection, required this.tlsClient});

  final ProtocolConnection connection;
  final AndroidAutoTlsClient tlsClient;

  Future<void> sendMessage({
    required int channel,
    required int messageId,
    required Uint8List protobufBody,
  }) async {
    if (channel < 0 || channel > 255) {
      throw ArgumentError.value(channel, 'channel');
    }
    if (messageId < 0 || messageId > 0xFFFF) {
      throw ArgumentError.value(messageId, 'messageId');
    }

    final Uint8List plaintext = Uint8List(2 + protobufBody.length);
    ByteData.sublistView(plaintext).setUint16(0, messageId, Endian.big);
    plaintext.setRange(2, plaintext.length, protobufBody);

    final Uint8List ciphertext = await tlsClient.encryptApplicationData(
      plaintext,
    );

    if (ciphertext.isEmpty) {
      throw StateError('TLS produced no application ciphertext.');
    }

    const int maxPayload = 0xFFFF;
    final MessageType messageType = channel == 0
        ? MessageType.control
        : MessageType.specific;

    if (ciphertext.length <= maxPayload) {
      await connection.send(
        ProtocolFrame(
          channel: channel,
          frameType: FrameType.bulk,
          messageType: messageType,
          encryptionType: EncryptionType.encrypted,
          payload: ciphertext,
        ),
      );
      return;
    }

    int offset = 0;
    final int firstLength = ciphertext.length < maxPayload
        ? ciphertext.length
        : maxPayload;

    await connection.send(
      ProtocolFrame(
        channel: channel,
        frameType: FrameType.first,
        messageType: messageType,
        encryptionType: EncryptionType.encrypted,
        totalMessageSize: ciphertext.length,
        payload: Uint8List.sublistView(ciphertext, 0, firstLength),
      ),
    );

    offset = firstLength;

    while (ciphertext.length - offset > maxPayload) {
      final int end = offset + maxPayload;

      await connection.send(
        ProtocolFrame(
          channel: channel,
          frameType: FrameType.middle,
          messageType: messageType,
          encryptionType: EncryptionType.encrypted,
          payload: Uint8List.sublistView(ciphertext, offset, end),
        ),
      );

      offset = end;
    }

    await connection.send(
      ProtocolFrame(
        channel: channel,
        frameType: FrameType.last,
        messageType: messageType,
        encryptionType: EncryptionType.encrypted,
        payload: Uint8List.sublistView(ciphertext, offset),
      ),
    );
  }
}
