import 'dart:typed_data';

import 'protocol_frame.dart';

class ProtocolMessage {
  const ProtocolMessage({
    required this.channel,
    required this.messageType,
    required this.encryptionType,
    required this.payload,
  });

  final int channel;
  final MessageType messageType;
  final EncryptionType encryptionType;
  final Uint8List payload;
}
