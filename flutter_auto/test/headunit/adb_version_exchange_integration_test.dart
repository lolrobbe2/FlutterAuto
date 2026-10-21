import 'dart:io';

import 'package:flutter_auto/headunit/message_router.dart';
import 'package:flutter_auto/headunit/protocol_connection.dart';
import 'package:flutter_auto/headunit/version_handshake.dart';
import 'package:flutter_auto/services/adb_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bool runAdbIntegration = bool.fromEnvironment('RUN_ADB_INTEGRATION');

  test(
    'negotiates protocol version with a real Android Auto phone over ADB',
    () async {
      final AdbManager adbManager = AdbManager();

      await adbManager.initializeAndroidAutoLink();

      final Socket socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5277,
        timeout: const Duration(seconds: 10),
      );

      final ProtocolConnection connection = ProtocolConnection(socket);
      final MessageRouter router = MessageRouter(connection);

      try {
        final VersionHandshake handshake = VersionHandshake(
          connection: connection,
          router: router,
          supportedMajorVersion: 1,
          supportedMinorVersion: 7,
          timeout: const Duration(seconds: 15),
        );

        final VersionHandshakeResult result = await handshake.run();

        expect(result.majorVersion, greaterThan(0));
        expect(result.status.value, 0);

        // A successful version exchange is required before TLS starts.
        print(
          'Android Auto version exchange succeeded: '
          '${result.majorVersion}.${result.minorVersion}',
        );
      } finally {
        await router.close();
        await connection.close();
      }
    },
    skip: runAdbIntegration
        ? false
        : 'Run with --dart-define=RUN_ADB_INTEGRATION=true',
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
