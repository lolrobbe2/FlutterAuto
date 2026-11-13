import 'dart:async';
import 'dart:io';

import 'rpc_connection.dart';

/// A loopback-only server for local headunit/application communication.
///
/// Binding to loopback is intentional: this server is not a network API.
class LocalRpcServer {
  final ServerSocket _serverSocket;
  final int _maxConnections;
  final StreamController<RpcConnection> _connections =
      StreamController<RpcConnection>.broadcast(sync: true);
  final Set<RpcConnection> _activeConnections = <RpcConnection>{};
  late final StreamSubscription<Socket> _serverSubscription;
  bool _closed = false;

  LocalRpcServer._(this._serverSocket, {required int maxConnections})
    : _maxConnections = maxConnections {
    _serverSubscription = _serverSocket.listen(_accept);
  }

  static Future<LocalRpcServer> bind({
    int port = 0,
    int maxConnections = 4,
  }) async {
    if (port < 0 || port > 65535) {
      throw ArgumentError.value(port, 'port');
    }
    if (maxConnections < 1) {
      throw ArgumentError.value(maxConnections, 'maxConnections');
    }

    final ServerSocket serverSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    return LocalRpcServer._(serverSocket, maxConnections: maxConnections);
  }

  String get host => InternetAddress.loopbackIPv4.address;

  int get port => _serverSocket.port;

  Stream<RpcConnection> get connections => _connections.stream;

  bool get isClosed => _closed;

  void _accept(Socket socket) {
    if (_closed || _activeConnections.length >= _maxConnections) {
      socket.destroy();
      return;
    }

    final RpcConnection connection = RpcConnection.fromSocket(socket);
    _activeConnections.add(connection);
    unawaited(
      connection.done.whenComplete(() {
        _activeConnections.remove(connection);
      }),
    );
    _connections.add(connection);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _serverSubscription.cancel();
    await _serverSocket.close();

    final List<RpcConnection> connections = _activeConnections.toList();
    await Future.wait<void>(
      connections.map((RpcConnection item) {
        return item.close();
      }),
    );
    _activeConnections.clear();
    await _connections.close();
  }
}
