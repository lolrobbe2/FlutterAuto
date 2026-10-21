import 'dart:async';
import 'dart:developer' as developer;

import 'package:logging/logging.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Logger.root.level = Level.ALL;

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

  await testMain();
}
