import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_auto_core/headunit/transport/protocol_transport.dart';

/// TCP implementation. Keeps the existing Socket-based connection usable.
class SocketProtocolTransport implements ProtocolTransport {
  SocketProtocolTransport(this._socket);

  final Socket _socket;

  @override
  Stream<List<int>> get input => _socket;

  @override
  Future<void> write(Uint8List bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> abort() async {
    _socket.destroy();
  }
}