import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_auto/headunit/message_router.dart';

import '../generated/oaa/control/ControlMessageIdsEnum.pbenum.dart';
import '../generated/oaa/control/VersionResponseStatusEnum.pbenum.dart';
import 'protocol_connection.dart';
import 'protocol_frame.dart';
import 'protocol_message.dart';

class VersionHandshakeResult {
  const VersionHandshakeResult({
    required this.majorVersion,
    required this.minorVersion,
    required this.status,
  });

  final int majorVersion;
  final int minorVersion;
  final ProtocolStatus_Enum status;
}

class VersionHandshake {
  VersionHandshake({
    required this.connection,
    required this.router,
    required this.supportedMajorVersion,
    required this.supportedMinorVersion,
    this.timeout = const Duration(seconds: 10),
  });

  final ProtocolConnection connection;
  final MessageRouter router;
  final int supportedMajorVersion;
  final int supportedMinorVersion;
  final Duration timeout;

  Future<VersionHandshakeResult> run() async {
    _validateVersion(supportedMajorVersion, 'major');
    _validateVersion(supportedMinorVersion, 'minor');

    final Future<ProtocolMessage> responseFuture = _waitForResponse();

    final Uint8List payload = Uint8List(6);
    final ByteData data = ByteData.sublistView(payload);

    data.setUint16(0, ControlMessage_Enum.VERSION_REQUEST.value, Endian.big);
    data.setUint16(2, supportedMajorVersion, Endian.big);
    data.setUint16(4, supportedMinorVersion, Endian.big);

    await connection.send(
      ProtocolFrame(
        channel: 0,
        frameType: FrameType.bulk,
        messageType: MessageType.specific,
        encryptionType: EncryptionType.plain,
        payload: payload,
      ),
    );

    final ProtocolMessage response = await responseFuture.timeout(timeout);

    if (response.channel != 0 || response.messageType != MessageType.specific) {
      throw const FormatException(
        'Version response was not received on the control channel.',
      );
    }

    if (response.encryptionType != EncryptionType.plain) {
      throw const FormatException('Expected an unencrypted version response.');
    }

    if (response.payload.length != 6) {
      throw FormatException(
        'Expected a 6-byte version response body, '
        'received ${response.payload.length} bytes.',
      );
    }

    final ByteData responseData = ByteData.sublistView(response.payload);
    final int majorVersion = responseData.getUint16(0, Endian.big);
    final int minorVersion = responseData.getUint16(2, Endian.big);
    final int statusValue = responseData.getUint16(4, Endian.big);

    final ProtocolStatus_Enum? status = ProtocolStatus_Enum.valueOf(
      statusValue,
    );

    if (status == null) {
      throw FormatException('Unknown version response status: $statusValue.');
    }

    if (status != ProtocolStatus_Enum.STATUS_SUCCESS) {
      throw FormatException(
        'Phone rejected the version handshake with status '
        '${status.name} ($statusValue).',
      );
    }

    return VersionHandshakeResult(
      majorVersion: majorVersion,
      minorVersion: minorVersion,
      status: status,
    );
  }

  Future<ProtocolMessage> _waitForResponse() {
    return router
        .forMessageId(ControlMessage_Enum.VERSION_RESPONSE.value, channel: 0)
        .first
        .then((ProtocolMessage message) {
          if (message.messageType != MessageType.control) {
            throw const FormatException(
              'Version response is not a control message.',
            );
          }

          if (message.encryptionType != EncryptionType.plain) {
            throw const FormatException(
              'Expected an unencrypted version response.',
            );
          }

          return ProtocolMessage(
            channel: message.channel,
            messageType: message.messageType,
            encryptionType: message.encryptionType,
            payload: Uint8List.fromList(message.payload.sublist(2)),
          );
        });
  }

  void _validateVersion(int version, String name) {
    if (version < 0 || version > 0xFFFF) {
      throw ArgumentError.value(
        version,
        name,
        'Must fit in an unsigned 16-bit integer.',
      );
    }
  }
}
