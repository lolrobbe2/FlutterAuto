import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_auto/screens/device_selection_screen.dart';
import 'package:flutter_auto/services/adb_manager.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('Main');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _initializeLogging();

  _log.info('Starting FlutterAuto...');

  final AdbManager adb = AdbManager();

  try {
    await adb.initializeAndroidAutoLink();

    _log.info(
      'Android Auto ADB initialization succeeded. '
      'Port forwarding is available at localhost:5277.',
    );
  } catch (error, stackTrace) {
    _log.severe('Failed to initialize Android Auto ADB.', error, stackTrace);
  }

  runApp(const MainApp());
}

/// Configures application-wide logging.
///
/// Call this once, before creating services that use Logger.
void _initializeLogging() {
  Logger.root.level = Level.INFO;

  Logger.root.onRecord.listen((LogRecord record) {
    developer.log(
      record.message,
      name: record.loggerName,
      time: record.time,
      level: record.level.value,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  });
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const DeviceSelectionScreen(),
    );
  }
}
