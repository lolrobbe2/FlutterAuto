import 'application_id.dart';
import 'application_lifecycle_state.dart';

class ApplicationLifecycleEvent {
  final ApplicationId applicationId;

  final ApplicationLifecycleState previousState;

  final ApplicationLifecycleState currentState;

  final DateTime timestamp;

  final String? reason;

  const ApplicationLifecycleEvent({
    required this.applicationId,
    required this.previousState,
    required this.currentState,
    required this.timestamp,
    this.reason,
  });
}
