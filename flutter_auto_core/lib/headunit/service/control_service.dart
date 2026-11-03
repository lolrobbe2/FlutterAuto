import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_auto_core/flutter_auto_core.dart';
import 'package:logging/logging.dart';

class ControlService extends ChannelService {
  ControlService({required this.registry}) : super(channelId: 0);
  static const int controlChannel = 0;
  static const int versionRequestId = 0x0001;
  static const int versionResponseId = 0x0002;
  static const int sslHandshakeId = 0x0003;
  static const int authCompleteId = 0x0004;
  static const int serviceDiscoveryRequestId = 0x0005;
  static const int serviceDiscoveryResponseId = 0x0006;

  final ChannelServiceRegistry registry;
  final Logger _log = Logger('ControlService');

  final Completer<ServiceDiscoveryRequest> _requestCompleter =
      Completer<ServiceDiscoveryRequest>();
  final Completer<ServiceDiscoveryResponse> _discoveryCompleter =
      Completer<ServiceDiscoveryResponse>();

  bool _discoveryResponseSent = false;

  Future<ServiceDiscoveryRequest> get phoneRequest => _requestCompleter.future;

  Future<ServiceDiscoveryResponse> get discoveryResponse =>
      _discoveryCompleter.future;

  Future<void> sendVersionRequest(int major, int minor) async {
    if(!(major >= 1 && minor >= 7)){
      _log.severe("incorrect minimum version");
      return;
    }
    final body = Uint8List(4);
    final data = ByteData.sublistView(body);
  
    data.setUint16(0, major, Endian.big);
    data.setUint16(2, minor, Endian.big);

    await sendMessage(
      messageId: versionRequestId,
      body: body,
      encryptionType: EncryptionType.plain,
      messageType: MessageType.specific,
    );
  }

  Future<void> sendTlsBytes(Uint8List tlsBytes) {
    return sendMessage(
      messageId: sslHandshakeId,
      body: tlsBytes,
      encryptionType: EncryptionType.plain,
      messageType: MessageType.specific,
    );
  }

  Stream<Uint8List> get incomingTlsBytes {
    return messagesForId(sslHandshakeId).map((message) {
      if (message.encryptionType != EncryptionType.plain) {
        throw const FormatException(
          'TLS handshake record must use plaintext transport framing.',
        );
      }
      return bodyOf(message);
    });
  }

  Future<void> sendAuthComplete(int status) {
    final body = AuthCompleteIndication(status: status).writeToBuffer();

    // Matches AASDK: AUTH_COMPLETE is plaintext + specific.
    return sendMessage(
      messageId: authCompleteId,
      body: body,
      encryptionType: EncryptionType.plain,
      messageType: MessageType.specific,
    );
  }

  @override
  Future<void> handleMessage(ProtocolMessage message) async {
    final int id = messageIdOf(message);

    if (id == ControlMessage_Enum.VERSION_RESPONSE.value) {
      _log.fine('Received VERSION_RESPONSE.');
      return;
    }
    if (id == ControlMessage_Enum.SSL_HANDSHAKE.value) {
      // TLS bytes are also exposed through incomingTlsBytes.
      _log.fine('Received SSL_HANDSHAKE (${bodyOf(message).length} bytes).');
      return;
    }
    if (id == ControlMessage_Enum.SERVICE_DISCOVERY_REQUEST.value) {
      await _handleServiceDiscoveryRequest(message);
      return;
    }
    if (id == ControlMessage_Enum.AUDIO_FOCUS_REQUEST.value) {
      await _handleAudioFocusRequest(message);
      return;
    }
    _log.warning(
      'Unhandled control message ID '
      '0x${id.toRadixString(16).padLeft(4, '0')}.',
    );
  }

  Future<void> _handleServiceDiscoveryRequest(ProtocolMessage message) async {
    if (_discoveryResponseSent) {
      _log.warning('Ignoring duplicate SERVICE_DISCOVERY_REQUEST.');
      return;
    }

    try {
      final request = ServiceDiscoveryRequest.fromBuffer(bodyOf(message));

      if (!_requestCompleter.isCompleted) {
        _requestCompleter.complete(request);
      }

      _log.info(
        'Phone discovery request: '
        '${request.deviceName} / ${request.deviceBrand}',
      );

      final response = ServiceDiscoveryResponse(
        channels: registry.buildDescriptors(),
        headUnitName: 'FlutterAuto',
        carModel: 'Android Auto Emulator',
        carYear: '2026',
        carSerial: 'FLUTTERAUTO-001',
        driverPosition: DriverPosition_Enum.LEFT,
        headunitManufacturer: 'FlutterAuto',
        headunitModel: 'FlutterAuto',
        swBuild: 'flutter-auto-dev',
        swVersion: '1.0.0',
        canPlayNativeMediaDuringVr: true,
        displayName: 'FlutterAuto',
      );

      // AASDK uses encrypted + specific for the discovery response.
      await sendMessage(
        messageId: serviceDiscoveryResponseId,
        body: response.writeToBuffer(),
        encryptionType: EncryptionType.encrypted,
        messageType: MessageType.specific,
      );

      _discoveryResponseSent = true;
      _discoveryCompleter.complete(response);

      _log.info(
        'Sent SERVICE_DISCOVERY_RESPONSE with '
        '${response.channels.length} channels.',
      );
    } catch (error, stackTrace) {
      if (!_discoveryCompleter.isCompleted) {
        _discoveryCompleter.completeError(error, stackTrace);
      }
      rethrow;
    }
  }

  Future<void> _handleAudioFocusRequest(ProtocolMessage message) async {
    AudioFocusRequest request = AudioFocusRequest.fromBuffer(bodyOf(message));
    
    final AudioFocusState_Enum focusState =
        request.audioFocusType == AudioFocusType_Enum.RELEASE
        ? AudioFocusState_Enum.LOSS
        : AudioFocusState_Enum.GAIN;

    _log.info(
      'Audio focus requested: ${request.audioFocusType.name}. '
      'Responding with: ${focusState.name}.',
    );

    final AudioFocusResponse response = AudioFocusResponse(
      audioFocusState: focusState,
    );
    await sendMessage(
      messageId: ControlMessage_Enum.AUDIO_FOCUS_RESPONSE.value,
      body: response.writeToBuffer(),
      encryptionType: EncryptionType.encrypted,
      messageType: MessageType.control,
    );
  }
}
