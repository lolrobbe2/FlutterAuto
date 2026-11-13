import '../application/application_id.dart';
import '../modules/module_id.dart';
import 'product_application.dart';
import 'product_id.dart';
import 'product_json_helpers.dart';
import 'product_module.dart';

class ProductManifest {
  static const int currentSchemaVersion = 1;

  static final RegExp _versionPattern = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$',
  );

  final ProductId id;
  final String name;
  final String version;
  final String minimumFrameworkVersion;

  final List<ProductApplication> applications;
  final List<ProductModule> modules;

  ProductManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.minimumFrameworkVersion,
    Iterable<ProductApplication> applications = const <ProductApplication>[],
    Iterable<ProductModule> modules = const <ProductModule>[],
  }) : applications = List<ProductApplication>.unmodifiable(applications),
       modules = List<ProductModule>.unmodifiable(modules) {
    if (name.trim().isEmpty) {
      throw ArgumentError('Product name cannot be empty.');
    }

    if (!_versionPattern.hasMatch(version)) {
      throw ArgumentError.value(
        version,
        'version',
        'Invalid semantic version.',
      );
    }

    if (!_versionPattern.hasMatch(minimumFrameworkVersion)) {
      throw ArgumentError.value(
        minimumFrameworkVersion,
        'minimumFrameworkVersion',
        'Invalid semantic version.',
      );
    }

    _validateUniqueApplications();
    _validateUniqueModules();
  }

  void _validateUniqueApplications() {
    final Set<ApplicationId> ids = <ApplicationId>{};
    final Set<String> paths = <String>{};

    for (final ProductApplication application in applications) {
      if (!ids.add(application.id)) {
        throw ArgumentError(
          'Duplicate product application ID: ${application.id}.',
        );
      }

      if (!paths.add(application.packagePath)) {
        throw ArgumentError(
          'Application package is referenced more than once: '
          '${application.packagePath}.',
        );
      }
    }
  }

  void _validateUniqueModules() {
    final Set<ModuleId> ids = <ModuleId>{};
    final Set<String> paths = <String>{};

    for (final ProductModule module in modules) {
      if (!ids.add(module.id)) {
        throw ArgumentError('Duplicate product module ID: ${module.id}.');
      }

      if (!paths.add(module.packagePath)) {
        throw ArgumentError(
          'Module package is referenced more than once: '
          '${module.packagePath}.',
        );
      }
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': currentSchemaVersion,
      'id': id.value,
      'name': name,
      'version': version,
      'minimumFrameworkVersion': minimumFrameworkVersion,
      'applications': applications
          .map((ProductApplication application) => application.toJson())
          .toList(),
      'modules': modules
          .map((ProductModule module) => module.toJson())
          .toList(),
    };
  }

  factory ProductManifest.fromJson(Map<String, Object?> json) {
    final Object? rawSchemaVersion = json['schemaVersion'];

    if (rawSchemaVersion != currentSchemaVersion) {
      throw FormatException(
        'Unsupported product manifest schema version: $rawSchemaVersion',
      );
    }

    final List<ProductApplication> applications =
        productReadOptionalList(json, 'applications').map((Object? value) {
          return ProductApplication.fromJson(
            productReadObject(value, 'applications[]'),
          );
        }).toList();

    final List<ProductModule> modules = productReadOptionalList(json, 'modules')
        .map((Object? value) {
          return ProductModule.fromJson(productReadObject(value, 'modules[]'));
        })
        .toList();

    return ProductManifest(
      id: ProductId(productReadRequiredString(json, 'id')),
      name: productReadRequiredString(json, 'name'),
      version: productReadRequiredString(json, 'version'),
      minimumFrameworkVersion: productReadRequiredString(
        json,
        'minimumFrameworkVersion',
      ),
      applications: applications,
      modules: modules,
    );
  }
}
