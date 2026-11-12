import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('ApplicationError', () {
    test('stores all supplied error information', () {
      final ApplicationId applicationId = ApplicationId('com.example.radio');

      final StateError error = StateError('Audio initialization failed');

      final StackTrace stackTrace = StackTrace.current;
      final DateTime timestamp = DateTime.now();

      final ApplicationError applicationError = ApplicationError(
        applicationId: applicationId,
        source: ApplicationErrorSource.startup,
        severity: ApplicationErrorSeverity.error,
        message: 'Failed to initialize audio',
        error: error,
        stackTrace: stackTrace,
        timestamp: timestamp,
      );

      expect(applicationError.applicationId, applicationId);
      expect(applicationError.source, ApplicationErrorSource.startup);
      expect(applicationError.severity, ApplicationErrorSeverity.error);
      expect(applicationError.message, 'Failed to initialize audio');
      expect(applicationError.error, same(error));
      expect(applicationError.stackTrace, same(stackTrace));
      expect(applicationError.timestamp, timestamp);
    });

    test('supports headunit-wide errors without an application ID', () {
      final ApplicationError applicationError = ApplicationError(
        applicationId: null,
        source: ApplicationErrorSource.runtime,
        severity: ApplicationErrorSeverity.critical,
        message: 'Runtime initialization failed',
        error: StateError('Initialization failed'),
        stackTrace: null,
        timestamp: DateTime.now(),
      );

      expect(applicationError.applicationId, isNull);
      expect(applicationError.source, ApplicationErrorSource.runtime);
      expect(applicationError.severity, ApplicationErrorSeverity.critical);
    });
  });
}
