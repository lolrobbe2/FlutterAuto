import 'package:headunit_contracts/headunit_contracts.dart';

class ApplicationRegistration {
  final ApplicationManifest manifest;

  final Set<CapabilityId> grantedCapabilities;

  ApplicationRegistration({
    required this.manifest,
    required Iterable<CapabilityId> grantedCapabilities,
  }) : grantedCapabilities =
           Set<CapabilityId>.unmodifiable(grantedCapabilities) {
    final Set<CapabilityId> requestedCapabilities =
        manifest.requestedCapabilities.toSet();

    final List<CapabilityId> invalidGrants =
        this.grantedCapabilities
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