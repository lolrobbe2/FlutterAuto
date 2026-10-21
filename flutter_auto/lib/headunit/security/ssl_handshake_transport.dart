import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../message_router.dart';
import '../protocol_connection.dart';
import '../protocol_frame.dart';
import '../protocol_message.dart';

class SslHandshakeTransport {
  SslHandshakeTransport({required this.connection, required this.router});

  static final Logger _log = Logger('SslHandshakeTransport');

  static const int sslHandshakeMessageId = 0x0003;

  final ProtocolConnection connection;
  final MessageRouter router;

  Future<void> sendTlsBytes(Uint8List tlsBytes) async {
    if (tlsBytes.isEmpty) {
      return;
    }

    _log.fine('[TLS transport] Sending ${tlsBytes.length} TLS bytes.');

    final Uint8List payload = Uint8List(2 + tlsBytes.length);
    final ByteData data = ByteData.sublistView(payload);

    data.setUint16(0, sslHandshakeMessageId, Endian.big);
    payload.setRange(2, payload.length, tlsBytes);

    await connection.send(
      ProtocolFrame(
        channel: 0,
        frameType: FrameType.bulk,
        messageType: MessageType.control,
        encryptionType: EncryptionType.plain,
        payload: payload,
      ),
    );
  }

  Stream<Uint8List> get incomingTlsBytes {
    return router.forMessageId(sslHandshakeMessageId, channel: 0).map((
      ProtocolMessage message,
    ) {
      _log.fine(
        '[TLS transport] Received message '
        'id=0x${sslHandshakeMessageId.toRadixString(16)}, '
        'payload=${message.payload.length} bytes, '
        'encryption=${message.encryptionType}.',
      );

      if (message.encryptionType != EncryptionType.plain) {
        throw const FormatException(
          'TLS handshake transport must be plaintext.',
        );
      }

      if (message.payload.length < 2) {
        throw const FormatException(
          'SSL_HANDSHAKE message is missing its message ID.',
        );
      }

      return Uint8List.fromList(message.payload.sublist(2));
    });
  }
}
