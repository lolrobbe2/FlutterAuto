import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_auto/headunit/headunit_session.dart';
import 'package:flutter_auto/headunit/message_router.dart';
import 'package:flutter_auto/headunit/protocol_connection.dart';
import 'package:flutter_auto/headunit/security/head_unit_identity.dart';
import 'package:flutter_auto/headunit/version_handshake.dart';
import 'package:flutter_auto/services/adb_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('AndroidAutoIntegrationTest');

void main() {
  const bool runAdbIntegration = bool.fromEnvironment('RUN_ADB_INTEGRATION');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Logger.root.level = Level.ALL;

    Logger.root.onRecord.listen((LogRecord record) {
      final String timestamp = record.time.toIso8601String();
      final String message =
          '$timestamp ${record.level.name} '
          '[${record.loggerName}] ${record.message}';

      developer.log(
        message,
        name: record.loggerName,
        level: record.level.value,
        error: record.error,
        stackTrace: record.stackTrace,
      );
    });
  });

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

        _log.info(
          'Android Auto version exchange succeeded: '
          '${result.majorVersion}.${result.minorVersion}',
        );
      } catch (error, stackTrace) {
        _log.severe(
          'Android Auto version negotiation failed.',
          error,
          stackTrace,
        );
        rethrow;
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

  test(
    'Android Auto head unit session connects over ADB',
    () async {
      final HeadunitSession session = HeadunitSession(
        adbManager: AdbManager(),
        host: InternetAddress.loopbackIPv4.address,
        port: 5277,
        configureAdb: true,
        identity: HeadUnitIdentity(),
        connectionTimeout: const Duration(seconds: 10),
      );

      try {
        final result = await session.connect().timeout(
          const Duration(seconds: 30),
        );

        expect(session.isConnected, isTrue);

        _log.info('Android Auto session connection succeeded: $result');
      } catch (error, stackTrace) {
        _log.severe(
          'Android Auto session connection failed.',
          error,
          stackTrace,
        );
        rethrow;
      } finally {
        await session.disconnect();
        await session.dispose();
      }
    },
    skip: runAdbIntegration
        ? false
        : 'Run with --dart-define=RUN_ADB_INTEGRATION=true',
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
