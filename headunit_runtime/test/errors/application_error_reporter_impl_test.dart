import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:headunit_runtime/src/errors/application_error_reporter_impl.dart';

void main() {
  group('ApplicationErrorReporterImpl', () {
    ApplicationError createError(String message) {
      return ApplicationError(
        applicationId: null,
        source: ApplicationErrorSource.runtime,
        severity: ApplicationErrorSeverity.error,
        message: message,
        error: Exception(message),
        stackTrace: null,
        timestamp: DateTime(2026, 1, 1),
      );
    }

    test('reports errors to multiple listeners', () async {
      final ApplicationErrorReporterImpl reporter =
          ApplicationErrorReporterImpl();

      final List<ApplicationError> firstListener = <ApplicationError>[];
      final List<ApplicationError> secondListener = <ApplicationError>[];

      reporter.errors.listen(firstListener.add);
      reporter.errors.listen(secondListener.add);

      final ApplicationError error = createError('Something failed');

      reporter.report(error);

      expect(firstListener, <ApplicationError>[error]);
      expect(secondListener, <ApplicationError>[error]);

      await reporter.dispose();
    });

    test('stores reported errors in recent history', () async {
      final ApplicationErrorReporterImpl reporter =
          ApplicationErrorReporterImpl();

      final ApplicationError error = createError('Something failed');

      reporter.report(error);

      expect(reporter.recentErrors, <ApplicationError>[error]);

      await reporter.dispose();
    });

    test('limits recent error history', () async {
      final ApplicationErrorReporterImpl reporter =
          ApplicationErrorReporterImpl(maxHistorySize: 2);

      final ApplicationError first = createError('First');
      final ApplicationError second = createError('Second');
      final ApplicationError third = createError('Third');

      reporter.report(first);
      reporter.report(second);
      reporter.report(third);

      expect(reporter.recentErrors, <ApplicationError>[second, third]);

      await reporter.dispose();
    });

    test('does not expose a modifiable history list', () async {
      final ApplicationErrorReporterImpl reporter =
          ApplicationErrorReporterImpl();

      reporter.report(createError('Something failed'));

      expect(() => reporter.recentErrors.clear(), throwsUnsupportedError);

      await reporter.dispose();
    });

    test('throws when reporting after disposal', () async {
      final ApplicationErrorReporterImpl reporter =
          ApplicationErrorReporterImpl();

      await reporter.dispose();

      expect(() => reporter.report(createError('Too late')), throwsStateError);
    });

    test('allows repeated disposal', () async {
      final ApplicationErrorReporterImpl reporter =
          ApplicationErrorReporterImpl();

      await reporter.dispose();
      await reporter.dispose();
    });
  });
}
