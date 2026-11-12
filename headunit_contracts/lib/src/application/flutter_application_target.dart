enum FlutterApplicationPlatform {
  android('android'),
  windows('windows');

  const FlutterApplicationPlatform(this.wireName);

  final String wireName;

  static FlutterApplicationPlatform fromWireName(String value) {
    for (final FlutterApplicationPlatform platform in values) {
      if (platform.wireName == value) {
        return platform;
      }
    }

    throw FormatException(
      'Unsupported Flutter application platform: $value',
    );
  }
}

class FlutterApplicationTarget {
  static final RegExp _architecturePattern = RegExp(
    r'^[a-z0-9][a-z0-9_-]*$',
  );

  final FlutterApplicationPlatform platform;

  /// Target CPU architecture, e.g. arm64-v8a or x64.
  final String architecture;

  /// Directory containing the complete platform-specific application bundle.
  final String bundlePath;

  /// Executable path relative to [bundlePath].
  ///
  /// Android: APK file.
  /// Windows: EXE file.
  final String entryPoint;

  FlutterApplicationTarget({
    required this.platform,
    required this.architecture,
    required this.bundlePath,
    required this.entryPoint,
  }) {
    if (!_architecturePattern.hasMatch(architecture)) {
      throw ArgumentError.value(
        architecture,
        'architecture',
        'Invalid architecture identifier.',
      );
    }

    _validateRelativePath(bundlePath, 'bundlePath');
    _validateRelativePath(entryPoint, 'entryPoint');

    if (platform == FlutterApplicationPlatform.android &&
        !entryPoint.toLowerCase().endsWith('.apk')) {
      throw ArgumentError.value(
        entryPoint,
        'entryPoint',
        'Android Flutter targets must point to an APK.',
      );
    }

    if (platform == FlutterApplicationPlatform.windows &&
        !entryPoint.toLowerCase().endsWith('.exe')) {
      throw ArgumentError.value(
        entryPoint,
        'entryPoint',
        'Windows Flutter targets must point to an EXE.',
      );
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'platform': platform.wireName,
      'architecture': architecture,
      'bundlePath': bundlePath,
      'entryPoint': entryPoint,
    };
  }

  factory FlutterApplicationTarget.fromJson(
    Map<String, Object?> json,
  ) {
    String requiredString(String key) {
      final Object? value = json[key];

      if (value is! String || value.isEmpty) {
        throw FormatException('Missing or invalid target field: $key');
      }

      return value;
    }

    return FlutterApplicationTarget(
      platform: FlutterApplicationPlatform.fromWireName(
        requiredString('platform'),
      ),
      architecture: requiredString('architecture'),
      bundlePath: requiredString('bundlePath'),
      entryPoint: requiredString('entryPoint'),
    );
  }

  static void _validateRelativePath(String path, String field) {
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
}