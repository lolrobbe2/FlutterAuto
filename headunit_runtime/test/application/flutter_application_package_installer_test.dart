import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:headunit_runtime/headunit_runtime.dart';

FlutterApplicationPackageManifest createManifest() {
  return FlutterApplicationPackageManifest(
    application: ApplicationManifest(
      id: ApplicationId('com.example.radio'),
      name: 'Radio',
      version: '1.0.0',
      minimumFrameworkVersion: '0.1.0',
      runtime: ApplicationRuntimeKind.flutter,
      iconPath: 'assets/icon.png',
    ),
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
}

List<ArchiveFile> createValidEntries() {
  return [
    ArchiveFile.string(
      'manifest.json',
      jsonEncode(createManifest().toJson()),
    ),
    ArchiveFile.string(
      'assets/icon.png',
      'fake icon',
    ),
    ArchiveFile.string(
      'artifacts/android/arm64-v8a/app.apk',
      'fake apk payload',
    ),
    ArchiveFile.string(
      'artifacts/windows/x64/radio.exe',
      'fake executable payload',
    ),
    ArchiveFile.string(
      'artifacts/windows/x64/flutter_windows.dll',
      'fake runtime payload',
    ),
    ArchiveFile.string(
      'artifacts/windows/x64/data/flutter_assets/AssetManifest.bin',
      'fake flutter assets',
    ),
  ];
}

Future<File> writeHapp(
  Directory directory, {
  required Iterable<ArchiveFile> entries,
}) async {
  final Archive archive = Archive();

  for (final ArchiveFile entry in entries) {
    archive.addFile(entry);
  }

  final List<int> bytes = ZipEncoder().encode(archive);

  final File file = File('${directory.path}/radio.happ');

  await file.writeAsBytes(bytes, flush: true);

  return file;
}

void main() {
  group('FlutterApplicationPackageInstaller', () {
    late Directory temporaryDirectory;
    late Directory applicationsDirectory;
    late FlutterApplicationPackageInstaller installer;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'flutter_auto_installer_test_',
      );

      applicationsDirectory = Directory(
        '${temporaryDirectory.path}/installed',
      );

      installer = FlutterApplicationPackageInstaller();
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('installs the Windows bundle and its dependencies', () async {
      final File packageFile = await writeHapp(
        temporaryDirectory,
        entries: createValidEntries(),
      );

      final InstalledFlutterApplication installed =
          await installer.install(
        packageFile: packageFile,
        applicationsDirectory: applicationsDirectory,
        platform: FlutterApplicationPlatform.windows,
        architecture: 'x64',
      );

      expect(installed.application.id.value, 'com.example.radio');
      expect(installed.target.platform, FlutterApplicationPlatform.windows);
      expect(installed.target.architecture, 'x64');

      expect(await installed.entryPoint.exists(), isTrue);

      expect(
        await File(
          '${installed.bundleDirectory.path}/flutter_windows.dll',
        ).exists(),
        isTrue,
      );

      expect(
        await File(
          '${installed.bundleDirectory.path}/data/flutter_assets/AssetManifest.bin',
        ).exists(),
        isTrue,
      );

      expect(
        await File(
          '${installed.applicationDirectory.path}/assets/icon.png',
        ).exists(),
        isTrue,
      );

      // The Android target must not be extracted.
      expect(
        await Directory(
          '${installed.applicationDirectory.path}/artifacts/android',
        ).exists(),
        isFalse,
      );

      expect(
        await installed.entryPoint.readAsString(),
        'fake executable payload',
      );
    });

    test('installs the Android APK without extracting Windows binaries',
        () async {
      final File packageFile = await writeHapp(
        temporaryDirectory,
        entries: createValidEntries(),
      );

      final InstalledFlutterApplication installed =
          await installer.install(
        packageFile: packageFile,
        applicationsDirectory: applicationsDirectory,
        platform: FlutterApplicationPlatform.android,
        architecture: 'arm64-v8a',
      );

      expect(installed.target.platform, FlutterApplicationPlatform.android);
      expect(installed.target.architecture, 'arm64-v8a');
      expect(await installed.entryPoint.exists(), isTrue);

      expect(
        await installed.entryPoint.readAsString(),
        'fake apk payload',
      );

      expect(
        await Directory(
          '${installed.applicationDirectory.path}/artifacts/windows',
        ).exists(),
        isFalse,
      );
    });

    test('rejects an unavailable platform architecture', () async {
      final File packageFile = await writeHapp(
        temporaryDirectory,
        entries: createValidEntries(),
      );

      await expectLater(
        installer.install(
          packageFile: packageFile,
          applicationsDirectory: applicationsDirectory,
          platform: FlutterApplicationPlatform.windows,
          architecture: 'arm64',
        ),
        throwsA(isA<FlutterApplicationInstallationException>()),
      );

      expect(
        await applicationsDirectory.list().toList(),
        isEmpty,
      );
    });

    test('does not overwrite an existing application', () async {
      final File packageFile = await writeHapp(
        temporaryDirectory,
        entries: createValidEntries(),
      );

      final InstalledFlutterApplication firstInstall =
          await installer.install(
        packageFile: packageFile,
        applicationsDirectory: applicationsDirectory,
        platform: FlutterApplicationPlatform.windows,
        architecture: 'x64',
      );

      await expectLater(
        installer.install(
          packageFile: packageFile,
          applicationsDirectory: applicationsDirectory,
          platform: FlutterApplicationPlatform.windows,
          architecture: 'x64',
        ),
        throwsA(isA<FlutterApplicationInstallationException>()),
      );

      expect(await firstInstall.entryPoint.exists(), isTrue);

      expect(
        await firstInstall.entryPoint.readAsString(),
        'fake executable payload',
      );

      expect(
        await applicationsDirectory.list().length,
        1,
      );
    });

    test('cleans up staging data when package validation fails', () async {
      final File packageFile = File(
        '${temporaryDirectory.path}/radio.happ',
      );

      await packageFile.writeAsString('invalid ZIP data');

      await expectLater(
        installer.install(
          packageFile: packageFile,
          applicationsDirectory: applicationsDirectory,
          platform: FlutterApplicationPlatform.windows,
          architecture: 'x64',
        ),
        throwsA(isA<FlutterApplicationPackageException>()),
      );

      expect(
        await applicationsDirectory.list().toList(),
        isEmpty,
      );
    });
  });
}