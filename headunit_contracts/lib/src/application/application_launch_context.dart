import '../capabilities/capability_id.dart';
import 'application_id.dart';

class ApplicationLaunchContext {
  final ApplicationId applicationId;

  final List<CapabilityId> grantedCapabilities;

  final String? locale;

  final String? productId;

  ApplicationLaunchContext({
    required this.applicationId,
    Iterable<CapabilityId> grantedCapabilities = const [],
    this.locale,
    this.productId,
  }) : grantedCapabilities =
           List<CapabilityId>.unmodifiable(grantedCapabilities);

  bool hasCapability(CapabilityId capability) {
    return grantedCapabilities.contains(capability);
  }
}