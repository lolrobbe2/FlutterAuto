import '../capabilities/capability_id.dart';
import 'application_id.dart';
import 'application_runtime_kind.dart';

class ApplicationManifest {
  static const int currentSchemaVersion = 1;

  static final RegExp _versionPattern = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$',
  );

  final ApplicationId id;

  final String name;

  final String version;

  final String minimumFrameworkVersion;

  final ApplicationRuntimeKind runtime;

  final String? entryPoint;

  final String? iconPath;

  final String? description;

  final List<CapabilityId> requestedCapabilities;

  ApplicationManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.minimumFrameworkVersion,
    required this.runtime,
    this.entryPoint,
    this.iconPath,
    this.description,
    Iterable<CapabilityId> requestedCapabilities = const [],
  }) : requestedCapabilities =
           List<CapabilityId>.unmodifiable(requestedCapabilities) {
    if (name.trim().isEmpty) {
      throw ArgumentError('Application name cannot be empty.');
    }

    if (!_versionPattern.hasMatch(version)) {
      throw ArgumentError.value(version, 'version', 'Invalid semantic version.');
    }

    if (!_versionPattern.hasMatch(minimumFrameworkVersion)) {
      throw ArgumentError.value(
        minimumFrameworkVersion,
        'minimumFrameworkVersion',
        'Invalid semantic version.',
      );
    }

    if (runtime == ApplicationRuntimeKind.web && entryPoint == null) {
      throw ArgumentError(
        'Web applications must define an entry point.',
      );
    }

    _validateRelativePath(entryPoint, 'entryPoint');
    _validateRelativePath(iconPath, 'iconPath');

    if (this.requestedCapabilities.toSet().length !=
        this.requestedCapabilities.length) {
      throw ArgumentError('Duplicate application capabilities.');
    }
  }

  static void _validateRelativePath(String? path, String field) {
    if (path == null) {
      return;
    }

    final List<String> segments = path.split('/');

    if (path.isEmpty ||
        path != path.trim() ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.contains(':') ||
        segments.any(
          (String segment) =>
              segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw ArgumentError.value(
        path,
        field,
        'Expected a safe relative package path.',
      );
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': currentSchemaVersion,
      'id': id.value,
      'name': name,
      'version': version,
      'minimumFrameworkVersion': minimumFrameworkVersion,
      'runtime': runtime.wireName,
      'entryPoint': entryPoint,
      'iconPath': iconPath,
      'description': description,
      'requestedCapabilities': requestedCapabilities
          .map((CapabilityId capability) => capability.value)
          .toList(),
    };
  }

  factory ApplicationManifest.fromJson(Map<String, Object?> json) {
    final Object? schemaVersion = json['schemaVersion'];

    if (schemaVersion != currentSchemaVersion) {
      throw FormatException(
        'Unsupported manifest schema version: $schemaVersion',
      );
    }

    final Object? rawCapabilities = json['requestedCapabilities'] ?? <Object?>[];

    if (rawCapabilities is! List) {
      throw FormatException('requestedCapabilities must be a list.');
    }

    final List<CapabilityId> capabilities = rawCapabilities.map(
      (Object? value) {
        if (value is! String) {
          throw FormatException('Invalid capability identifier.');
        }

        return CapabilityId(value);
      },
    ).toList();

    String requiredString(String key) {
      final Object? value = json[key];

      if (value is! String || value.isEmpty) {
        throw FormatException('Missing or invalid field: $key');
      }

      return value;
    }

    String? optionalString(String key) {
      final Object? value = json[key];

      if (value == null) {
        return null;
      }

      if (value is! String) {
        throw FormatException('Invalid field: $key');
      }

      return value;
    }

    return ApplicationManifest(
      id: ApplicationId(requiredString('id')),
      name: requiredString('name'),
      version: requiredString('version'),
      minimumFrameworkVersion: requiredString('minimumFrameworkVersion'),
      runtime: ApplicationRuntimeKind.fromWireName(
        requiredString('runtime'),
      ),
      entryPoint: optionalString('entryPoint'),
      iconPath: optionalString('iconPath'),
      description: optionalString('description'),
      requestedCapabilities: capabilities,
    );
  }
}