import 'service_id.dart';

import '../application/application_id.dart';
import '../capabilities/capability_id.dart';
import 'service_key.dart';

abstract interface class ServiceBroker {
  ApplicationId get applicationId;

  T getService<T extends Object>(ServiceKey<T> key);

  bool hasCapability(CapabilityId capability);
}

class ServiceNotFoundException implements Exception {
  final String serviceId;

  const ServiceNotFoundException(this.serviceId);

  @override
  String toString() => 'Service not found: $serviceId';
}

class ServiceAccessDeniedException implements Exception {
  final ApplicationId applicationId;
  final ServiceId serviceId;
  final List<CapabilityId> missingCapabilities;

  const ServiceAccessDeniedException({
    required this.applicationId,
    required this.serviceId,
    required this.missingCapabilities,
  });

  @override
  String toString() {
    return 'Application $applicationId does not have permission '
        'to access $serviceId. Missing capabilities: '
        '${missingCapabilities.join(', ')}';
  }
}

class ServiceTypeMismatchException implements Exception {
  final ServiceId serviceId;
  final String expectedType;
  final String actualType;

  const ServiceTypeMismatchException({
    required this.serviceId,
    required this.expectedType,
    required this.actualType,
  });

  @override
  String toString() {
    return 'Service $serviceId has type $actualType, '
        'but $expectedType was requested.';
  }
}