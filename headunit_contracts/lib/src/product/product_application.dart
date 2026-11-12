import '../application/application_background_policy.dart';
import '../application/application_id.dart';
import '../application/application_manifest.dart';
import '../capabilities/capability_id.dart';
import 'product_json_helpers.dart';
import 'product_package_path.dart';

class ProductApplication {
  final ApplicationId id;
  final String packagePath;
  final bool enabled;
  final ApplicationBackgroundPolicy backgroundPolicy;
  final Set<CapabilityId> grantedCapabilities;

  ProductApplication({
    required this.id,
    required this.packagePath,
    this.enabled = true,
    this.backgroundPolicy = ApplicationBackgroundPolicy.keepMounted,
    Iterable<CapabilityId> grantedCapabilities = const <CapabilityId>[],
  }) : grantedCapabilities = _immutableCapabilities(grantedCapabilities) {
    validateProductPackagePath(packagePath, requiredExtension: '.happ');
  }

  static Set<CapabilityId> _immutableCapabilities(
    Iterable<CapabilityId> capabilities,
  ) {
    final List<CapabilityId> copied = capabilities.toList();

    if (copied.toSet().length != copied.length) {
      throw ArgumentError('Duplicate granted capabilities.');
    }

    return Set<CapabilityId>.unmodifiable(copied);
  }

  /// Checks the product's grants against the application's own manifest.
  ///
  /// The product may grant only capabilities requested by the application.
  void validateAgainstManifest(ApplicationManifest manifest) {
    if (manifest.id != id) {
      throw FormatException(
        'Product application ID $id does not match package manifest ID '
        '${manifest.id}.',
      );
    }

    final Set<CapabilityId> requested = manifest.requestedCapabilities.toSet();

    final List<CapabilityId> invalidGrants = grantedCapabilities
        .where((CapabilityId capability) => !requested.contains(capability))
        .toList();

    if (invalidGrants.isNotEmpty) {
      throw FormatException(
        'Product grants capabilities not requested by $id: '
        '${invalidGrants.join(', ')}.',
      );
    }
  }

  Map<String, Object?> toJson() {
    final List<String> capabilities =
        grantedCapabilities
            .map((CapabilityId capability) => capability.value)
            .toList()
          ..sort();

    return <String, Object?>{
      'id': id.value,
      'packagePath': packagePath,
      'enabled': enabled,
      'backgroundPolicy': backgroundPolicy.wireName,
      'grantedCapabilities': capabilities,
    };
  }

  factory ProductApplication.fromJson(Map<String, Object?> json) {
    final List<CapabilityId> capabilities =
        productReadOptionalList(json, 'grantedCapabilities').map((
          Object? value,
        ) {
          if (value is! String) {
            throw FormatException('Invalid granted capability.');
          }

          return CapabilityId(value);
        }).toList();

    final Object? rawBackgroundPolicy = json['backgroundPolicy'];

    ApplicationBackgroundPolicy backgroundPolicy =
        ApplicationBackgroundPolicy.keepMounted;

    if (rawBackgroundPolicy != null) {
      if (rawBackgroundPolicy is! String) {
        throw FormatException('Invalid backgroundPolicy.');
      }

      backgroundPolicy = ApplicationBackgroundPolicy.fromWireName(
        rawBackgroundPolicy,
      );
    }

    return ProductApplication(
      id: ApplicationId(productReadRequiredString(json, 'id')),
      packagePath: productReadRequiredString(json, 'packagePath'),
      enabled: productReadOptionalBool(json, 'enabled', defaultValue: true),
      backgroundPolicy: backgroundPolicy,
      grantedCapabilities: capabilities,
    );
  }
}
