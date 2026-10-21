import 'dart:async';
import 'dart:io';

import 'package:flutter_auto/headunit/message_router.dart';
import 'package:flutter_auto/headunit/security/android_auto_tls_client.dart';
import 'package:flutter_auto/headunit/security/head_unit_identity.dart';
import 'package:flutter_auto/headunit/security/ssl_handshake_transport.dart';
import 'package:flutter_auto/services/adb_manager.dart';

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

  HeadunitSessionState _state = HeadunitSessionState.disconnected;
  ProtocolConnection? _connection;
  AndroidAutoTlsClient? _tlsClient;
  MessageRouter? _router;

  Future<void>? _disconnectFuture;
  bool _disposed = false;

  HeadunitSessionState get state => _state;

  Stream<HeadunitSessionState> get states => _stateController.stream;

  ProtocolConnection? get connection => _connection;

  MessageRouter? get router => _router;

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
