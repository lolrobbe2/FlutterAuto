import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:headunit_runtime/src/errors/application_error_reporter_impl.dart';
import 'package:headunit_runtime/src/errors/flutter_framework_error_handler.dart';

void main() {
  group('FlutterFrameworkErrorHandler', () {
    late ApplicationErrorReporterImpl reporter;
    late FlutterFrameworkErrorHandler handler;
    late FlutterExceptionHandler? originalHandler;

    setUp(() {
      originalHandler = FlutterError.onError;

      reporter = ApplicationErrorReporterImpl();

      handler = FlutterFrameworkErrorHandler(errorReporter: reporter);
    });

    tearDown(() async {
      handler.dispose();

      FlutterError.onError = originalHandler;

      await reporter.dispose();
    });

    test('reports Flutter framework errors', () {
      FlutterError.onError = (_) {};

      handler.install();

      final StateError originalError = StateError('Widget build failed.');

      final StackTrace originalStackTrace = StackTrace.current;

      FlutterError.reportError(
        FlutterErrorDetails(
          exception: originalError,
          stack: originalStackTrace,
          library: 'Headunit test',
        ),
      );

      expect(reporter.recentErrors, hasLength(1));

      final ApplicationError reportedError = reporter.recentErrors.single;

      expect(reportedError.applicationId, isNull);
      expect(reportedError.source, ApplicationErrorSource.widget);
      expect(reportedError.severity, ApplicationErrorSeverity.error);
      expect(reportedError.error, same(originalError));
      expect(reportedError.stackTrace, same(originalStackTrace));
      expect(reportedError.message, contains('Widget build failed.'));
    });

    test('forwards errors to the previous Flutter error handler', () {
      FlutterErrorDetails? receivedDetails;

      FlutterError.onError = (FlutterErrorDetails details) {
        receivedDetails = details;
      };

      handler.install();

      final StateError originalError = StateError('Test error');

      final FlutterErrorDetails details = FlutterErrorDetails(
        exception: originalError,
      );

      FlutterError.reportError(details);

      expect(receivedDetails, same(details));
    });

    test('restores the previous handler when disposed', () {
      void previousHandler(FlutterErrorDetails details) {}

      FlutterError.onError = previousHandler;

      handler.install();
      handler.dispose();

      expect(FlutterError.onError, same(previousHandler));
    });

    test('does not overwrite a handler installed afterwards', () {
      handler.install();

      void replacementHandler(FlutterErrorDetails details) {}

      FlutterError.onError = replacementHandler;

      handler.dispose();

      expect(FlutterError.onError, same(replacementHandler));
    });

    test('installation is idempotent', () {
      FlutterError.onError = (_) {};

      handler.install();

      final FlutterExceptionHandler? installedHandler = FlutterError.onError;

      handler.install();

      expect(FlutterError.onError, same(installedHandler));
    });

    test('cannot be installed after disposal', () {
      handler.dispose();

      expect(handler.install, throwsStateError);
    });

    test('disposal is idempotent', () {
      handler.install();

      handler.dispose();
      handler.dispose();

      expect(reporter.recentErrors, isEmpty);
    });
  });
}
