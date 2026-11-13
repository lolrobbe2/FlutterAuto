import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '_media_socket.dart';
import '_media_wire.dart';
import 'media_stream_configuration.dart';
import 'media_stream_connection.dart';
import 'media_transport_exception.dart';

/// Localhost-only media listener for one remote application session.
class LocalMediaServer {
  static const int defaultMaxAccessUnitBytes = 2 * 1024 * 1024;

  final ServerSocket _serverSocket;
  final String _token;
  final VideoStreamConfiguration configuration;
  final int _maxConnections;
  final int _maxQueuedFrames;
  final int _maxAccessUnitBytes;
  final StreamController<MediaStreamConnection> _connections =
      StreamController<MediaStreamConnection>.broadcast(sync: true);
  final Set<MediaStreamConnection> _activeConnections =
      <MediaStreamConnection>{};
  int _pendingConnections = 0;
  final Set<Socket> _pendingSockets = <Socket>{};
  late final StreamSubscription<Socket> _subscription;
  bool _closed = false;

  LocalMediaServer._({
    required ServerSocket serverSocket,
    required String token,
    required this.configuration,
    required int maxConnections,
    required int maxQueuedFrames,
    required int maxAccessUnitBytes,
  }) : _serverSocket = serverSocket,
       _token = token,
       _maxConnections = maxConnections,
       _maxQueuedFrames = maxQueuedFrames,
       _maxAccessUnitBytes = maxAccessUnitBytes {
    _subscription = _serverSocket.listen(_accept);
  }

  static Future<LocalMediaServer> bind({
    required String token,
    VideoStreamConfiguration configuration =
        VideoStreamConfiguration.defaultConfiguration,
    int maxConnections = 1,
    int maxQueuedFrames = 2,
    int maxAccessUnitBytes = defaultMaxAccessUnitBytes,
  }) async {
    if (token.length < 16 || token.length > 512) {
      throw ArgumentError.value(token, 'token');
    }
    configuration.validate();
    if (maxConnections < 1 || maxConnections > 4) {
      throw ArgumentError.value(maxConnections, 'maxConnections');
    }
    if (maxQueuedFrames < 1 || maxQueuedFrames > 8) {
      throw ArgumentError.value(maxQueuedFrames, 'maxQueuedFrames');
    }
    if (maxAccessUnitBytes < 1024 || maxAccessUnitBytes > 16 * 1024 * 1024) {
      throw ArgumentError.value(maxAccessUnitBytes, 'maxAccessUnitBytes');
    }
    final ServerSocket socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    return LocalMediaServer._(
      serverSocket: socket,
      token: token,
      configuration: configuration,
      maxConnections: maxConnections,
      maxQueuedFrames: maxQueuedFrames,
      maxAccessUnitBytes: maxAccessUnitBytes,
    );
  }

  String get host => InternetAddress.loopbackIPv4.address;
  int get port => _serverSocket.port;
  bool get isClosed => _closed;
  Stream<MediaStreamConnection> get connections => _connections.stream;

  void _accept(Socket socket) {
    if (_closed ||
        _activeConnections.length + _pendingConnections >= _maxConnections) {
      socket.destroy();
      return;
    }
    _pendingConnections++;
    _pendingSockets.add(socket);
    unawaited(_authenticate(socket));
  }

  Future<void> _authenticate(Socket socket) async {
    final MediaSocketChannel channel = MediaSocketChannel(
      socket,
      maxRecordBytes: _maxAccessUnitBytes + videoFrameHeaderBytes,
      maxBufferedWriteBytes: _maxAccessUnitBytes + 1024,
    );
    try {
      final Uint8List? hello = await channel
          .readRecord(maximumBytes: 516)
          .timeout(const Duration(seconds: 5));
      if (hello == null) {
        throw const MediaTransportException('Missing media handshake.');
      }
      final String suppliedToken = decodeHello(hello);
      if (!constantTimeTokenEquals(suppliedToken, _token)) {
        throw const MediaTransportException('Media authentication failed.');
      }
      await channel.writeRecord(<Uint8List>[
        encodeConfiguration(configuration),
      ], payloadLength: 14);
      if (_closed || _activeConnections.length >= _maxConnections) {
        await channel.close();
        return;
      }
      final MediaStreamConnection connection =
          MediaStreamConnection.fromAuthenticatedChannel(
            channel: channel,
            configuration: configuration,
            maxAccessUnitBytes: _maxAccessUnitBytes,
            maxQueuedFrames: _maxQueuedFrames,
            onClosed: (MediaStreamConnection item) {
              _activeConnections.remove(item);
            },
          );
      _activeConnections.add(connection);
      _connections.add(connection);
      connection.start();
    } catch (_) {
      await channel.close();
    } finally {
      _pendingConnections--;
      _pendingSockets.remove(socket);
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription.cancel();
    await _serverSocket.close();
    for (final Socket socket in _pendingSockets) {
      socket.destroy();
    }
    _pendingSockets.clear();
    final List<MediaStreamConnection> connections = _activeConnections.toList(
      growable: false,
    );
    await Future.wait<void>(
      connections.map((MediaStreamConnection item) {
        return item.close();
      }),
    );
    _activeConnections.clear();
    await _connections.close();
  }
}
