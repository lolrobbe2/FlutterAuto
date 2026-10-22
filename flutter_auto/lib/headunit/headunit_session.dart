import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_auto/generated/oaa/control/AuthCompleteIndicationMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ServiceDiscoveryResponseMessage.pb.dart';
import 'package:flutter_auto/headunit/message_router.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';
import 'package:flutter_auto/headunit/security/android_auto_tls_client.dart';
import 'package:flutter_auto/headunit/security/head_unit_identity.dart';
import 'package:flutter_auto/headunit/security/ssl_handshake_transport.dart';
import 'package:flutter_auto/headunit/service/input_service.dart';
import 'package:flutter_auto/headunit/service/media_audio_service.dart';
import 'package:flutter_auto/headunit/service/sensor_service.dart';
import 'package:flutter_auto/headunit/service/service_manager.dart';
import 'package:flutter_auto/headunit/service/video_service.dart';
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

class HeadunitSession {
  final Logger _log = Logger('HeadunitSession');
  HeadunitSession({
    required this.adbManager,
    HeadUnitIdentity? identity,
    this.host = '127.0.0.1',
    this.port = 5277,
    this.majorVersion = 1,
    this.minorVersion = 1,
    this.configureAdb = true,
    this.connectionTimeout = const Duration(seconds: 10),
  }) : identity = identity ?? HeadUnitIdentity();

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

  final inputService = InputService();
  final sensorService = SensorService();
  final videoService = VideoService();
  final mediaAudioService = MediaAudioService();

  HeadunitSessionState _state = HeadunitSessionState.disconnected;
  ProtocolConnection? _connection;
  AndroidAutoTlsClient? _tlsClient;
  MessageRouter? _router;
  ServiceManager? _serviceManager;

  Future<void>? _disconnectFuture;
  bool _disposed = false;

  HeadunitSessionState get state => _state;

  Stream<HeadunitSessionState> get states => _stateController.stream;

  ProtocolConnection? get connection => _connection;
  MessageRouter? get router => _router;
  ServiceManager? get serviceManager => _serviceManager;

  bool get isConnected => _state == HeadunitSessionState.connected;

  void _setState(HeadunitSessionState nextState) {
    if (_disposed || _state == nextState) {
      return;
    }

    _state = nextState;
    _stateController.add(nextState);
  }

  /// Configures ADB forwarding, opens the TCP connection,
  /// and negotiates the Android Auto protocol version.
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

      final Socket socket = await Socket.connect(
        host,
        port,
        timeout: connectionTimeout,
      );

      final ProtocolConnection protocolConnection = ProtocolConnection(socket);
      final MessageRouter messageRouter = MessageRouter(protocolConnection);

      _connection = protocolConnection;
      _router = messageRouter;

      // Monitor the lifetime of the TCP connection.
      protocolConnection.done.then((_) {
        if (identical(_connection, protocolConnection) &&
            _state != HeadunitSessionState.disconnecting &&
            _state != HeadunitSessionState.failed) {
          _connection = null;
          _router = null;
          _setState(HeadunitSessionState.disconnected);
          unawaited(messageRouter.close());
        }
      });

      _setState(HeadunitSessionState.negotiatingVersion);

      final VersionHandshakeResult result = await VersionHandshake(
        connection: protocolConnection,
        router: messageRouter,
        supportedMajorVersion: majorVersion,
        supportedMinorVersion: minorVersion,
      ).run();

      if (protocolConnection.isClosed) {
        throw StateError(
          'The protocol connection closed during version negotiation.',
        );
      }
      await identity.ensureIdentity();
      await identity.debugCertificatePem();
      final SslHandshakeTransport tlsTransport = SslHandshakeTransport(
        connection: protocolConnection,
        router: messageRouter,
      );

      final AndroidAutoTlsClient tlsClient = AndroidAutoTlsClient(
        transport: tlsTransport,
        identityStore: identity,
      );

      _tlsClient = tlsClient;
      await tlsClient.connect();

      if (protocolConnection.isClosed) {
        throw StateError(
          'The protocol connection closed during TLS negotiation.',
        );
      }

      messageRouter.setApplicationDecryptor(tlsClient.decryptApplicationData);
      Future<void> sendControlPayload(Uint8List payload) async {
        if (!tlsClient.isConnected || protocolConnection.isClosed) {
          throw StateError(
            'Cannot send application data: the connection is not ready.',
          );
        }

        final Uint8List encryptedPayload = await tlsClient
            .encryptApplicationData(payload);

        await protocolConnection.send(
          ProtocolFrame(
            channel: 0,
            frameType: FrameType.bulk,
            messageType: MessageType.control,
            encryptionType: EncryptionType.encrypted,
            payload: encryptedPayload,
          ),
        );
      }

      final ServiceManager serviceManager = ServiceManager(
        router: messageRouter,
        sendControlPayload: sendControlPayload,
      );
      final Uint8List authProtobuf = AuthCompleteIndication(
        status: 1,
      ).writeToBuffer();

      final Uint8List authPayload = Uint8List(2 + authProtobuf.length);
      ByteData.sublistView(authPayload).setUint16(0, 0x0004, Endian.big);
      authPayload.setRange(2, authPayload.length, authProtobuf);

      // Send through the existing TLS-protected control-message path.
      _serviceManager = serviceManager;
      serviceManager.registerService(
        name: InputService.serviceName,
        channelId: InputService.defaultChannelId,
        buildDescriptor: inputService.buildDescriptor,
      );

      serviceManager.registerService(
        name: SensorService.serviceName,
        channelId: SensorService.defaultChannelId,
        buildDescriptor: sensorService.buildDescriptor,
      );

      serviceManager.registerService(
        name: VideoService.serviceName,
        channelId: VideoService.defaultChannelId,
        buildDescriptor: videoService.buildDescriptor,
      );

      serviceManager.registerService(
        name: MediaAudioService.serviceName,
        channelId: MediaAudioService.defaultChannelId,
        buildDescriptor: mediaAudioService.buildDescriptor,
      );

      serviceManager.start(); // Register the 0x0005 listener first.
      await sendControlPayload(authPayload);

      // Send 0x0006 immediately, advertising all registered services.
      final ServiceDiscoveryResponse response = await serviceManager.discover();
      final phoneRequest = await serviceManager.waitForPhoneRequest();
      _log.info('Advertised ${response.channels.length} local channels.');

      _setState(HeadunitSessionState.connected);
      return result;
    } catch (_) {
      final ProtocolConnection? currentConnection = _connection;
      final MessageRouter? currentRouter = _router;
      final AndroidAutoTlsClient? currentTlsClient = _tlsClient;
      if (currentTlsClient != null) {
        await currentTlsClient.close();
      }

      if (currentRouter != null) {
        await currentRouter.close();
      }

      if (currentConnection != null) {
        await currentConnection.close();
      }
      _tlsClient = null;
      _connection = null;
      _router = null;

      _setState(HeadunitSessionState.failed);
      rethrow;
    }
  }

  /// Closes the router and protocol connection, then resets the session.
  Future<void> disconnect() {
    final Future<void>? existingFuture = _disconnectFuture;

    if (existingFuture != null) {
      return existingFuture;
    }

    _disconnectFuture = _disconnectInternal();
    return _disconnectFuture!;
  }

  Future<void> _disconnectInternal() async {
    if (_disposed) {
      return;
    }

    _setState(HeadunitSessionState.disconnecting);

    final ProtocolConnection? currentConnection = _connection;
    final MessageRouter? currentRouter = _router;
    final AndroidAutoTlsClient? currentTlsClient = _tlsClient;

    _tlsClient = null;
    _connection = null;
    _router = null;

    try {
      if (currentTlsClient != null) {
        await currentTlsClient.close();
      }

      if (currentRouter != null) {
        await currentRouter.close();
      }

      if (currentConnection != null) {
        await currentConnection.close();
      }
    } finally {
      _setState(HeadunitSessionState.disconnected);
      _disconnectFuture = null;
    }
  }

  /// Releases session resources. Call when the session is no longer used.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    await disconnect();
    _disposed = true;
    await _stateController.close();
  }
}
