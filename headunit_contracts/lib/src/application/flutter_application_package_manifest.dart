import 'application_manifest.dart';
import 'application_runtime_kind.dart';
import 'flutter_application_target.dart';

class FlutterApplicationPackageManifest {
  static const int currentFormatVersion = 1;

  final ApplicationManifest application;
  final List<FlutterApplicationTarget> targets;

  FlutterApplicationPackageManifest({
    required this.application,
    required Iterable<FlutterApplicationTarget> targets,
  }) : targets = List<FlutterApplicationTarget>.unmodifiable(targets) {
    if (application.runtime != ApplicationRuntimeKind.flutter) {
      throw ArgumentError(
        'Flutter application packages must use the Flutter runtime.',
      );
    }

    if (this.targets.isEmpty) {
      throw ArgumentError(
        'A Flutter application package must define at least one target.',
      );
    }

    final Set<String> targetKeys = <String>{};

    for (final FlutterApplicationTarget target in this.targets) {
      final String key =
          '${target.platform.wireName}:${target.architecture}';

      if (!targetKeys.add(key)) {
        throw ArgumentError(
          'Duplicate Flutter application target: $key.',
        );
      }
    }
  }

  FlutterApplicationTarget? targetFor({
    required FlutterApplicationPlatform platform,
    required String architecture,
  }) {
    for (final FlutterApplicationTarget target in targets) {
      if (target.platform == platform &&
          target.architecture == architecture) {
        return target;
      }
    }

    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'formatVersion': currentFormatVersion,
      'application': application.toJson(),
      'targets': targets
          .map(
            (FlutterApplicationTarget target) => target.toJson(),
          )
          .toList(),
    };
  }

  factory FlutterApplicationPackageManifest.fromJson(
    Map<String, Object?> json,
  ) {
    final Object? formatVersion = json['formatVersion'];

    if (formatVersion != currentFormatVersion) {
      throw FormatException(
        'Unsupported HAPP format version: $formatVersion',
      );
    }

    final Map<String, Object?> applicationJson = _readObject(
      json['application'],
      'application',
    );

    final Object? rawTargets = json['targets'];

    if (rawTargets is! List) {
      throw FormatException('targets must be a list.');
    }

    final List<FlutterApplicationTarget> targets =
        rawTargets.map((Object? value) {
      return FlutterApplicationTarget.fromJson(
        _readObject(value, 'target'),
      );
    }).toList();

    return FlutterApplicationPackageManifest(
      application: ApplicationManifest.fromJson(applicationJson),
      targets: targets,
    );
  }

  static Map<String, Object?> _readObject(
    Object? value,
    String field,
  ) {
    if (value is! Map) {
      throw FormatException('$field must be an object.');
    }

    final Map<String, Object?> result = <String, Object?>{};

    for (final Object? key in value.keys) {
      if (key is! String) {
        throw FormatException('$field contains a non-string key.');
      }

      result[key] = value[key];
    }

    return result;
  }
}