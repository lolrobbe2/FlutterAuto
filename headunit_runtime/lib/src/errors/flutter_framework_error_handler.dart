import 'package:flutter/foundation.dart';
import 'package:headunit_contracts/headunit_contracts.dart';

class FlutterFrameworkErrorHandler {
  final ApplicationErrorReporter _errorReporter;

  FlutterExceptionHandler? _previousHandler;

  bool _installed = false;
  bool _disposed = false;

  late final FlutterExceptionHandler _installedHandler = _handleError;

  FlutterFrameworkErrorHandler({
    required ApplicationErrorReporter errorReporter,
  }) : _errorReporter = errorReporter;

  void install() {
    if (_disposed) {
      throw StateError(
        'Cannot install a disposed FlutterFrameworkErrorHandler.',
      );
    }

    if (_installed) {
      return;
    }

    _previousHandler = FlutterError.onError;
    FlutterError.onError = _installedHandler;

    _installed = true;
  }

  void _handleError(FlutterErrorDetails details) {
    if (!_disposed) {
      try {
        final String context = details.context?.toDescription() ?? '';
        final String exception = details.exceptionAsString();

        final String message = context.isEmpty
            ? exception
            : '$context: $exception';

        _errorReporter.report(
          ApplicationError(
            applicationId: null,
            source: ApplicationErrorSource.widget,
            severity: ApplicationErrorSeverity.error,
            message: message,
            error: details.exception,
            stackTrace: details.stack,
            timestamp: DateTime.now(),
          ),
        );
      } catch (_) {
        // Reporting must never prevent Flutter's original error handler
        // from receiving the exception.
      }
    }

    final FlutterExceptionHandler? previousHandler = _previousHandler;

    if (previousHandler != null) {
      previousHandler(details);
    } else {
      FlutterError.presentError(details);
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    // Do not overwrite a handler installed by another component after ours.
    if (_installed &&
        identical(FlutterError.onError, _installedHandler)) {
      FlutterError.onError = _previousHandler;
    }

    _installed = false;
  }
}