
import 'dart:io';

import 'package:flutter_auto_core/flutter_auto_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('AndroidAutoIntegrationTest');

// Run against a connected Android Auto phone with:
// flutter test test/headunit/headunit_adb_test.dart \
//   --dart-define=RUN_ADB_INTEGRATION=true

void main() {
  const bool runAdbIntegration = bool.fromEnvironment(
    'RUN_ADB_INTEGRATION',
    defaultValue: false,
  );

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Logger.root.level = Level.ALL;

    Logger.root.onRecord.listen((LogRecord record) {
      final String timestamp = record.time.toIso8601String();
      final String message =
          '$timestamp ${record.level.name} '
          '[${record.loggerName}] ${record.message}';

      // ignore: avoid_print
      print(message);

      if (record.error != null) {
        // ignore: avoid_print
        print('Error: ${record.error}');
      }

      if (record.stackTrace != null) {
        // ignore: avoid_print
        print(record.stackTrace);
      }
    });
  });

  test(
    'negotiates protocol version with a real Android Auto phone over ADB',
    () async {
      final adbManager = AdbManager();
      await adbManager.initializeAndroidAutoLink();

      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5277,
        timeout: const Duration(seconds: 10),
      );

      final connection = ProtocolConnection(socket);
      final router = MessageRouter(connection);
      final sender = ProtocolMessageSender(connection);

      final registry = ChannelServiceRegistry(
        router: router,
        sender: sender,
      );

      final controlService = ControlService(
        registry: registry,
      );

      try {
        // Register channel 0 and start the central router before sending
        // VERSION_REQUEST, so a fast VERSION_RESPONSE cannot be missed.
        registry.register(controlService);
        registry.start();

        final handshake = VersionHandshake(
          controlService: controlService,
          supportedMajorVersion: 1,
          supportedMinorVersion: 7,
          timeout: const Duration(seconds: 15),
        );

        final result = await handshake.run();

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
        await registry.dispose();
        await controlService.dispose();
        await router.close();
        await connection.close();
      }
    },
    skip: !runAdbIntegration
        ? 'Run with --dart-define=RUN_ADB_INTEGRATION=true'
        : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'Android Auto head unit session connects over ADB',
    () async {
      final session = HeadunitSession(
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

        _log.info(
          'Android Auto session connection succeeded: $result',
        );
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
    skip: !runAdbIntegration
        ? 'Run with --dart-define=RUN_ADB_INTEGRATION=true'
        : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
