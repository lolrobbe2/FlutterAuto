import 'package:headunit_shared/headunit_shared_io.dart';

class ApplicationRegistration {
  final ApplicationManifest manifest;

  final Set<CapabilityId> grantedCapabilities;

  final ApplicationBackgroundPolicy backgroundPolicy;

  ApplicationRegistration({
    required this.manifest,
    required Iterable<CapabilityId> grantedCapabilities,
    this.backgroundPolicy = ApplicationBackgroundPolicy.keepMounted,
  }) : grantedCapabilities = Set<CapabilityId>.unmodifiable(
         grantedCapabilities,
       ) {
    final Set<CapabilityId> requestedCapabilities = manifest
        .requestedCapabilities
        .toSet();

    final List<CapabilityId> invalidGrants = this.grantedCapabilities
        .where(
          (CapabilityId capability) =>
              !requestedCapabilities.contains(capability),
        )
        .toList();

    if (invalidGrants.isNotEmpty) {
      throw ArgumentError(
        'Cannot grant capabilities that the application did not request: '
        '${invalidGrants.join(', ')}',
      );
    }
  }
}
