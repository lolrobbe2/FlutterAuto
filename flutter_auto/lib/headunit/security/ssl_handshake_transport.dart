import 'dart:typed_data';

import 'package:flutter_auto/headunit/service/control_service.dart';

class SslHandshakeTransport {
  SslHandshakeTransport({required this.controlService});

  final ControlService controlService;

  Future<void> sendTlsBytes(Uint8List bytes) {
    return controlService.sendTlsBytes(bytes);
  }

  Stream<Uint8List> get incomingTlsBytes =>
      controlService.incomingTlsBytes;
}
