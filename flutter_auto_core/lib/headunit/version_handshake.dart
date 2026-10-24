
import 'dart:async';
import 'dart:typed_data';

import 'protocol_frame.dart';
import 'protocol_message.dart';
import 'service/control_service.dart';

import '../generated/oaa/control/VersionResponseStatusEnum.pbenum.dart';

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
    required this.controlService,
    required this.supportedMajorVersion,
    required this.supportedMinorVersion,
    this.timeout = const Duration(seconds: 10),
  });

  final ControlService controlService;
  final int supportedMajorVersion;
  final int supportedMinorVersion;
  final Duration timeout;

  Future<VersionHandshakeResult> run() async {
    _validateVersion(supportedMajorVersion, 'major');
    _validateVersion(supportedMinorVersion, 'minor');

    // Subscribe before sending to avoid missing a fast response.
    final Future<ProtocolMessage> responseFuture =
        controlService.waitForMessage(
      ControlService.versionResponseId,
    );

    // ControlService owns the message ID, framing, and transport.
    await controlService.sendVersionRequest(
      supportedMajorVersion,
      supportedMinorVersion,
    );

    final ProtocolMessage response =
        await responseFuture.timeout(timeout);

    if (response.channel != ControlService.controlChannel) {
      throw FormatException(
        'VERSION_RESPONSE arrived on channel ${response.channel}, '
        'expected ${ControlService.controlChannel}.',
      );
    }

    if (response.messageType != MessageType.specific) {
      throw const FormatException(
        'VERSION_RESPONSE must use MessageType.specific.',
      );
    }

    if (response.encryptionType != EncryptionType.plain) {
      throw const FormatException(
        'VERSION_RESPONSE must be unencrypted.',
      );
    }

    // ControlService removes the two-byte message ID.
    final Uint8List body = controlService.bodyOf(response);

    if (body.length != 6) {
      throw FormatException(
        'Expected a 6-byte version response body, '
        'received ${body.length} bytes.',
      );
    }

    final ByteData data = ByteData.sublistView(body);
    final int majorVersion = data.getUint16(0, Endian.big);
    final int minorVersion = data.getUint16(2, Endian.big);
    final int statusValue = data.getUint16(4, Endian.big);

    final ProtocolStatus_Enum? status =
        ProtocolStatus_Enum.valueOf(statusValue);

    if (status == null) {
      throw FormatException(
        'Unknown version response status: $statusValue.',
      );
    }

    if (status != ProtocolStatus_Enum.STATUS_SUCCESS) {
      throw FormatException(
        'Phone rejected version negotiation with '
        '${status.name} ($statusValue).',
      );
    }

    return VersionHandshakeResult(
      majorVersion: majorVersion,
      minorVersion: minorVersion,
      status: status,
    );
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
