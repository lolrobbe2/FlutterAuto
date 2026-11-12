import 'package:headunit_contracts/headunit_contracts.dart';

enum ApplicationManagerEventType {
  applicationsChanged,
  foregroundChanged,
}

class ApplicationManagerEvent {
  final ApplicationManagerEventType type;
  final ApplicationId? applicationId;
  final ApplicationId? previousForegroundApplicationId;
  final ApplicationId? foregroundApplicationId;
  final DateTime timestamp;

  const ApplicationManagerEvent({
    required this.type,
    required this.timestamp,
    this.applicationId,
    this.previousForegroundApplicationId,
    this.foregroundApplicationId,
  });
}