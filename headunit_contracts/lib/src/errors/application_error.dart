
import '../application/application_id.dart';
import 'application_error_severity.dart';
import 'application_error_source.dart';

class ApplicationError {
  final ApplicationId? applicationId;
  final ApplicationErrorSource source;
  final ApplicationErrorSeverity severity;

  final String message;
  final Object error;
  final StackTrace? stackTrace;

  final DateTime timestamp;

  const ApplicationError({
    required this.applicationId,
    required this.source,
    required this.severity,
    required this.message,
    required this.error,
    required this.stackTrace,
    required this.timestamp,
  });
}
