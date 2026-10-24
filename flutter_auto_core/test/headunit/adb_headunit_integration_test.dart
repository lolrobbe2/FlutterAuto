import 'dart:io';

import 'package:flutter_auto_core/flutter_auto_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AdbManager adbManager;
  ProtocolConnection? connection;

  setUp(() {
    adbManager = AdbManager();
  });

  tearDown(() async {
    await connection?.close();
  });

  test(
    'connects to the forwarded Android Auto TCP port',
    () async {
      // Ensure ADB is running and the port forward is configured.
      await adbManager.initializeAndroidAutoLink();

      // Connect to the local end of the ADB port forward.
      final Socket socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5277,
        timeout: const Duration(seconds: 5),
      );

      connection = ProtocolConnection(socket);

      expect(connection!.isClosed, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
