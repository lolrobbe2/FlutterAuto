import 'dart:async';
import 'dart:io';

import 'package:flutter_auto/generated/oaa/video/VideoFPSEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/video/VideoResolutionEnum.pbenum.dart';
import 'package:flutter_auto/headunit/message_router.dart';
import 'package:flutter_auto/headunit/protocol_message_sender.dart';
import 'package:flutter_auto/headunit/security/android_auto_tls_client.dart';
import 'package:flutter_auto/headunit/security/head_unit_identity.dart';
import 'package:flutter_auto/headunit/security/ssl_handshake_transport.dart';
import 'package:flutter_auto/headunit/service/channel_service_registry.dart';
import 'package:flutter_auto/headunit/service/control_service.dart';
import 'package:flutter_auto/headunit/service/input_service.dart';
import 'package:flutter_auto/headunit/service/media_audio_service.dart';
import 'package:flutter_auto/headunit/service/microphone_service.dart';
import 'package:flutter_auto/headunit/service/sensor_service.dart';
import 'package:flutter_auto/headunit/service/system_audio_service.dart';
import 'package:flutter_auto/headunit/service/video_service.dart';
import 'package:flutter_auto/headunit/service/voice_service.dart';
import 'package:flutter_auto/services/adb_manager.dart';
import 'package:logging/logging.dart';

import 'protocol_connection.dart';
import 'version_handshake.dart';

enum HeadunitSessionState {
  disconnected,
  connecting,
  negotiatingVersion,
  connected,
  disconnecting,
  failed,
}

enum StatusCode {
  ok(0),
  unsolicitedMessage(1),
  noCompatibleVersion(-1),
  certificateError(-2),
  authenticationFailure(-3),
  invalidService(-4),
  invalidChannel(-5),
  invalidPriority(-6),
  internalError(-7),
  mediaConfigMismatch(-8),
  invalidSensor(-9),
  bluetoothPairingDelayed(-10),
  bluetoothUnavailable(-11),
  bluetoothInvalidAddress(-12),
  bluetoothInvalidPairingMethod(-13),
  bluetoothInvalidAuthData(-14),
  bluetoothAuthDataMismatch(-15),
  bluetoothHfpAnotherConnection(-16),
  bluetoothHfpConnectionFailure(-17),
  keycodeNotBound(-18),
  radioInvalidStation(-19),
  invalidInput(-20),
  radioStationPresetsNotSupported(-21),
  radioCommError(-22),
  certNotYetValid(-23),
  certExpired(-24),
  pingTimeout(-25),
  carPropertySetFailed(-26),
  carPropertyListenerFailed(-27),
  commandNotSupported(-250),
  framingError(-251),
  unexpectedMessage(-253),
  busy(-254),
  outOfMemory(-255);

  const StatusCode(this.value);

  final int value;
}

class HeadunitSession {
  HeadunitSession({
    required this.adbManager,
    HeadUnitIdentity? identity,
    this.host = '127.0.0.1',
    this.port = 5277,
    this.majorVersion = 1,
    this.minorVersion = 1,
    this.configureAdb = true,
    this.connectionTimeout = const Duration(seconds: 10),
    VideoResolution_Enum videoResolution = VideoResolution_Enum.VIDEO_800x480,
    VideoFPS_Enum videoFps = VideoFPS_Enum.x30_,
    int videoDpi = 140,
  }) : identity = identity ?? HeadUnitIdentity(),
       videoService = VideoService(
         resolution: videoResolution,
         fps: videoFps,
         dpi: videoDpi,
       );

  final Logger _log = Logger('HeadunitSession');

  final HeadUnitIdentity identity;
  final AdbManager adbManager;

  final String host;
  final int port;
  final int majorVersion;
  final int minorVersion;
  final bool configureAdb;
  final Duration connectionTimeout;

  final StreamController<HeadunitSessionState> _stateController =
      StreamController<HeadunitSessionState>.broadcast();

  // Channel services are long-lived and may be reused across connections.
  final inputService = InputService();
  final sensorService = SensorService();
  final mediaAudioService = MediaAudioService();
  final speechAudioService = SpeechAudioService();
  final systemAudioService = SystemAudioService();
  final microphoneInputService = MicrophoneInputService();
  VideoService videoService;

  HeadunitSessionState _state = HeadunitSessionState.disconnected;

  ProtocolConnection? _connection;
  MessageRouter? _router;
  ProtocolMessageSender? _sender;
  ChannelServiceRegistry? _registry;
  ControlService? _controlService;
  AndroidAutoTlsClient? _tlsClient;

  Future<void>? _disconnectFuture;
  bool _disposed = false;

  HeadunitSessionState get state => _state;

  Stream<HeadunitSessionState> get states => _stateController.stream;

  bool get isConnected => _state == HeadunitSessionState.connected;

  ProtocolConnection? get connection => _connection;
  MessageRouter? get router => _router;
  ProtocolMessageSender? get sender => _sender;
  ChannelServiceRegistry? get channelRegistry => _registry;
  ControlService? get controlService => _controlService;

  void _setState(HeadunitSessionState nextState) {
    if (_disposed || _state == nextState) return;

    _state = nextState;
    _stateController.add(nextState);
  }

  Future<VersionHandshakeResult> connect() async {
    if (_disposed) {
      throw StateError('This HeadunitSession has been disposed.');
    }

    if (_state != HeadunitSessionState.disconnected) {
      throw StateError('Cannot connect while the session is $_state.');
    }

    _setState(HeadunitSessionState.connecting);

    try {
      if (configureAdb) {
        await adbManager.initializeAndroidAutoLink();
      }

      final socket = await Socket.connect(
        host,
        port,
        timeout: connectionTimeout,
      );

      final connection = ProtocolConnection(socket);
      final router = MessageRouter(connection);
      final sender = ProtocolMessageSender(connection);

      // Registry and channel 0 control service are created before
      // version negotiation so every inbound message uses the same route.
      final registry = ChannelServiceRegistry(router: router, sender: sender);

      final controlService = ControlService(registry: registry);

      _connection = connection;
      _router = router;
      _sender = sender;
      _registry = registry;
      _controlService = controlService;

      connection.done.then((_) async {
        if (!identical(_connection, connection) ||
            _state == HeadunitSessionState.disconnecting ||
            _state == HeadunitSessionState.failed) {
          return;
        }

        _log.warning('Protocol connection closed by remote peer.');

        final currentRegistry = _registry;
        final currentControlService = _controlService;

        _connection = null;
        _router = null;
        _sender = null;
        _registry = null;
        _controlService = null;
        _tlsClient = null;

        _setState(HeadunitSessionState.disconnected);

        await currentRegistry?.dispose();
        await currentControlService?.dispose();
        await router.close();
      });

      // Register the control service on channel 0 just like every
      // data service. It owns version, TLS, auth, and discovery messages.
      registry.register(controlService);

      registry.register(inputService);
      registry.register(sensorService);
      registry.register(videoService);
      registry.register(mediaAudioService);
      registry.register(speechAudioService);
      registry.register(systemAudioService);
      registry.register(microphoneInputService);

      // Route all incoming messages before sending the version request.
      registry.start();

      _setState(HeadunitSessionState.negotiatingVersion);

      final versionResult = await VersionHandshake(
        controlService: controlService,
        supportedMajorVersion: majorVersion,
        supportedMinorVersion: minorVersion,
        timeout: connectionTimeout,
      ).run();

      if (connection.isClosed) {
        throw StateError(
          'The protocol connection closed during version negotiation.',
        );
      }

      // Identity and certificate provisioning remain session-level
      // responsibilities, not channel-message responsibilities.
      await identity.ensureIdentity();
      await identity.debugCertificatePem();

      final tlsTransport = SslHandshakeTransport(
        controlService: controlService,
      );

      final tlsClient = AndroidAutoTlsClient(
        transport: tlsTransport,
        identityStore: identity,
      );
      router.setApplicationDecryptor(tlsClient.decryptApplicationData);
      _tlsClient = tlsClient;

      // SSL_HANDSHAKE messages travel through ControlService.
      await tlsClient.connect();

      if (connection.isClosed) {
        throw StateError(
          'The protocol connection closed during TLS negotiation.',
        );
      }

      // Encryption is enabled only after the TLS handshake completes.
      sender.setApplicationEncryptor(tlsClient.encryptApplicationData);

      router.setApplicationDecryptor(tlsClient.decryptApplicationData);

      // ControlService chooses the required framing for AUTH_COMPLETE:
      // message ID 0x0004, plaintext, MessageType.specific.
      await controlService.sendAuthComplete(StatusCode.ok.value);

      // The control service receives 0x0005 and sends the encrypted
      // 0x0006 response itself. No response is built in this class.
      final response = await controlService.discoveryResponse.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Timed out waiting for service discovery to complete.',
        ),
      );

      final phoneRequest = await controlService.phoneRequest;

      _log.info(
        'Service discovery completed: '
        '${response.channels.length} channels advertised.',
      );
      _log.info(
        'Phone: ${phoneRequest.deviceName} / '
        '${phoneRequest.deviceBrand}',
      );

      _setState(HeadunitSessionState.connected);
      return versionResult;
    } catch (error, stackTrace) {
      _log.severe('Headunit session connection failed.', error, stackTrace);

      await _cleanupConnection(failedState: HeadunitSessionState.failed);

      rethrow;
    }
  }

  Future<void> _cleanupConnection({
    required HeadunitSessionState failedState,
  }) async {
    final tlsClient = _tlsClient;
    final registry = _registry;
    final controlService = _controlService;
    final router = _router;
    final connection = _connection;

    // Clear references first, preventing connection callbacks from
    // disposing the same objects a second time.
    _tlsClient = null;
    _registry = null;
    _controlService = null;
    _sender = null;
    _router = null;
    _connection = null;

    try {
      await tlsClient?.close();
    } catch (error, stackTrace) {
      _log.warning('Error closing TLS client.', error, stackTrace);
    }

    try {
      await registry?.dispose();
    } catch (error, stackTrace) {
      _log.warning('Error disposing channel registry.', error, stackTrace);
    }

    try {
      await controlService?.dispose();
    } catch (error, stackTrace) {
      _log.warning('Error disposing control service.', error, stackTrace);
    }

    try {
      await router?.close();
    } catch (error, stackTrace) {
      _log.warning('Error closing message router.', error, stackTrace);
    }

    try {
      await connection?.close();
    } catch (error, stackTrace) {
      _log.warning('Error closing protocol connection.', error, stackTrace);
    }

    _setState(failedState);
  }

  Future<void> disconnect() {
    final existingFuture = _disconnectFuture;
    if (existingFuture != null) return existingFuture;

    _disconnectFuture = _disconnectInternal();
    return _disconnectFuture!;
  }

  Future<void> _disconnectInternal() async {
    if (_disposed) return;

    _setState(HeadunitSessionState.disconnecting);

    try {
      await _cleanupConnection(failedState: HeadunitSessionState.disconnected);
    } finally {
      _disconnectFuture = null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;

    await disconnect();
    _disposed = true;

    // Dispose the persistent data services only when the whole session
    // object is no longer going to be reused.
    await inputService.dispose();
    await sensorService.dispose();
    await videoService.dispose();
    await mediaAudioService.dispose();
    await speechAudioService.dispose();
    await systemAudioService.dispose();
    await microphoneInputService.dispose();

    await _stateController.close();
  }
}
