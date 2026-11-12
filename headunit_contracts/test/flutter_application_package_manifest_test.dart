import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:test/test.dart';

ApplicationManifest createApplicationManifest({
  ApplicationRuntimeKind runtime = ApplicationRuntimeKind.flutter,
  String? entryPoint,
}) {
  return ApplicationManifest(
    id: ApplicationId('com.example.radio'),
    name: 'Radio',
    version: '1.0.0',
    minimumFrameworkVersion: '0.1.0',
    runtime: runtime,
    entryPoint: entryPoint,
  );
}

void main() {
  group('FlutterApplicationPackageManifest', () {
    late FlutterApplicationPackageManifest manifest;

    setUp(() {
      manifest = FlutterApplicationPackageManifest(
        application: createApplicationManifest(),
        targets: [
          FlutterApplicationTarget(
            platform: FlutterApplicationPlatform.android,
            architecture: 'arm64-v8a',
            bundlePath: 'artifacts/android/arm64-v8a',
            entryPoint: 'app.apk',
          ),
          FlutterApplicationTarget(
            platform: FlutterApplicationPlatform.windows,
            architecture: 'x64',
            bundlePath: 'artifacts/windows/x64',
            entryPoint: 'radio.exe',
          ),
        ],
      );
    });

    test('serializes and deserializes package manifest', () {
      final Map<String, Object?> json = manifest.toJson();

      final FlutterApplicationPackageManifest restored =
          FlutterApplicationPackageManifest.fromJson(json);

      expect(restored.toJson(), equals(json));
    });

    test('finds the exact platform and architecture target', () {
      final FlutterApplicationTarget? androidTarget = manifest.targetFor(
        platform: FlutterApplicationPlatform.android,
        architecture: 'arm64-v8a',
      );

      expect(androidTarget, isNotNull);
      expect(androidTarget!.entryPoint, 'app.apk');

      final FlutterApplicationTarget? windowsTarget = manifest.targetFor(
        platform: FlutterApplicationPlatform.windows,
        architecture: 'x64',
      );

      expect(windowsTarget, isNotNull);
      expect(windowsTarget!.entryPoint, 'radio.exe');
    });

    test('returns null for an unavailable target', () {
      expect(
        manifest.targetFor(
          platform: FlutterApplicationPlatform.windows,
          architecture: 'arm64',
        ),
        isNull,
      );
    });

    test('rejects duplicate platform and architecture targets', () {
      expect(
        () => FlutterApplicationPackageManifest(
          application: createApplicationManifest(),
          targets: [
            FlutterApplicationTarget(
              platform: FlutterApplicationPlatform.windows,
              architecture: 'x64',
              bundlePath: 'artifacts/first',
              entryPoint: 'first.exe',
            ),
            FlutterApplicationTarget(
              platform: FlutterApplicationPlatform.windows,
              architecture: 'x64',
              bundlePath: 'artifacts/second',
              entryPoint: 'second.exe',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects packages without targets', () {
      expect(
        () => FlutterApplicationPackageManifest(
          application: createApplicationManifest(),
          targets: [],
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-Flutter application manifests', () {
      expect(
        () => FlutterApplicationPackageManifest(
          application: createApplicationManifest(
            runtime: ApplicationRuntimeKind.web,
            entryPoint: 'web/index.html',
          ),
          targets: [
            FlutterApplicationTarget(
              platform: FlutterApplicationPlatform.windows,
              architecture: 'x64',
              bundlePath: 'artifacts/windows/x64',
              entryPoint: 'radio.exe',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects unsafe bundle paths', () {
      expect(
        () => FlutterApplicationTarget(
          platform: FlutterApplicationPlatform.windows,
          architecture: 'x64',
          bundlePath: 'artifacts/../../outside',
          entryPoint: 'radio.exe',
        ),
        throwsArgumentError,
      );
    });

    test('rejects an executable with the wrong platform extension', () {
      expect(
        () => FlutterApplicationTarget(
          platform: FlutterApplicationPlatform.android,
          architecture: 'arm64-v8a',
          bundlePath: 'artifacts/android',
          entryPoint: 'radio.exe',
        ),
        throwsArgumentError,
      );
    });

    test('rejects unsupported package format versions', () {
      final Map<String, Object?> json = manifest.toJson();
      json['formatVersion'] = 999;

      expect(
        () => FlutterApplicationPackageManifest.fromJson(json),
        throwsFormatException,
      );
    });
  });
}