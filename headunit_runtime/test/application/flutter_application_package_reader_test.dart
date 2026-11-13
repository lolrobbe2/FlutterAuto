import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_runtime/headunit_runtime.dart';

FlutterApplicationPackageManifest createManifest() {
  return FlutterApplicationPackageManifest(
    application: ApplicationManifest(
      id: ApplicationId('com.example.radio'),
      name: 'Radio',
      version: '1.0.0',
      minimumFrameworkVersion: '0.1.0',
      runtime: ApplicationRuntimeKind.flutter,
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
    ArchiveFile.string('manifest.json', jsonEncode(createManifest().toJson())),
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
  ];
}

Future<File> writeHapp(
  Directory directory, {
  String filename = 'radio.happ',
  required Iterable<ArchiveFile> entries,
}) async {
  final Archive archive = Archive();

  for (final ArchiveFile entry in entries) {
    archive.addFile(entry);
  }

  final List<int> bytes = ZipEncoder().encode(archive);

  final File file = File('${directory.path}/$filename');

  await file.writeAsBytes(bytes, flush: true);

  return file;
}

void main() {
  group('FlutterApplicationPackageReader', () {
    late Directory temporaryDirectory;
    late FlutterApplicationPackageReader reader;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'flutter_auto_happ_test_',
      );

      reader = FlutterApplicationPackageReader();
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('reads a valid package with Android and Windows targets', () async {
      final File file = await writeHapp(
        temporaryDirectory,
        entries: createValidEntries(),
      );

      final FlutterApplicationPackage package = await reader.read(file);

      expect(package.manifest.application.name, 'Radio');
      expect(package.manifest.targets, hasLength(2));

      expect(
        package.manifest
            .targetFor(
              platform: FlutterApplicationPlatform.android,
              architecture: 'arm64-v8a',
            )
            ?.entryPoint,
        'app.apk',
      );

      expect(
        package.manifest
            .targetFor(
              platform: FlutterApplicationPlatform.windows,
              architecture: 'x64',
            )
            ?.entryPoint,
        'radio.exe',
      );

      expect(package.archiveSizeBytes, greaterThan(0));
    });

    test('rejects a file without the happ extension', () async {
      final File file = await writeHapp(
        temporaryDirectory,
        filename: 'radio.zip',
        entries: createValidEntries(),
      );

      await expectLater(
        reader.read(file),
        throwsA(isA<FlutterApplicationPackageException>()),
      );
    });

    test('rejects an invalid ZIP archive', () async {
      final File file = File('${temporaryDirectory.path}/invalid.happ');

      await file.writeAsString('not a ZIP archive');

      await expectLater(
        reader.read(file),
        throwsA(isA<FlutterApplicationPackageException>()),
      );
    });

    test('rejects an archive without a root manifest', () async {
      final File file = await writeHapp(
        temporaryDirectory,
        entries: [ArchiveFile.string('readme.txt', 'No manifest here')],
      );

      await expectLater(
        reader.read(file),
        throwsA(isA<FlutterApplicationPackageException>()),
      );
    });

    test('rejects a package with an invalid manifest', () async {
      final File file = await writeHapp(
        temporaryDirectory,
        entries: [ArchiveFile.string('manifest.json', 'not valid JSON')],
      );

      await expectLater(
        reader.read(file),
        throwsA(isA<FlutterApplicationPackageException>()),
      );
    });

    test('rejects a package with a missing Windows executable', () async {
      final List<ArchiveFile> entries = createValidEntries()
          .where(
            (ArchiveFile entry) =>
                entry.name != 'artifacts/windows/x64/radio.exe',
          )
          .toList();

      final File file = await writeHapp(temporaryDirectory, entries: entries);

      await expectLater(
        reader.read(file),
        throwsA(isA<FlutterApplicationPackageException>()),
      );
    });

    test('rejects a package with a missing Android APK', () async {
      final List<ArchiveFile> entries = createValidEntries()
          .where(
            (ArchiveFile entry) =>
                entry.name != 'artifacts/android/arm64-v8a/app.apk',
          )
          .toList();

      final File file = await writeHapp(temporaryDirectory, entries: entries);

      await expectLater(
        reader.read(file),
        throwsA(isA<FlutterApplicationPackageException>()),
      );
    });

    test('rejects path traversal entries', () async {
      final List<ArchiveFile> entries = createValidEntries()
        ..add(ArchiveFile.string('../outside.txt', 'outside the package'));

      final File file = await writeHapp(temporaryDirectory, entries: entries);

      await expectLater(
        reader.read(file),
        throwsA(isA<FlutterApplicationPackageException>()),
      );
    });

    test('rejects case-insensitive duplicate paths', () async {
      final List<ArchiveFile> entries = createValidEntries()
        ..add(ArchiveFile.string('Assets/icon.png', 'first'))
        ..add(ArchiveFile.string('assets/Icon.png', 'second'));

      final File file = await writeHapp(temporaryDirectory, entries: entries);

      await expectLater(
        reader.read(file),
        throwsA(isA<FlutterApplicationPackageException>()),
      );
    });

    test('rejects an archive exceeding its entry limit', () async {
      final File file = await writeHapp(
        temporaryDirectory,
        entries: createValidEntries(),
      );

      final FlutterApplicationPackageReader limitedReader =
          FlutterApplicationPackageReader(maxArchiveEntries: 2);

      await expectLater(
        limitedReader.read(file),
        throwsA(isA<FlutterApplicationPackageException>()),
      );
    });

    test('rejects an archive exceeding its expanded size limit', () async {
      final File file = await writeHapp(
        temporaryDirectory,
        entries: createValidEntries(),
      );

      final FlutterApplicationPackageReader limitedReader =
          FlutterApplicationPackageReader(maxExpandedSizeBytes: 32);

      await expectLater(
        limitedReader.read(file),
        throwsA(isA<FlutterApplicationPackageException>()),
      );
    });

    test('rejects an archive exceeding its compressed size limit', () async {
      final File file = await writeHapp(
        temporaryDirectory,
        entries: createValidEntries(),
      );

      final FlutterApplicationPackageReader limitedReader =
          FlutterApplicationPackageReader(maxPackageSizeBytes: 10);

      await expectLater(
        limitedReader.read(file),
        throwsA(isA<FlutterApplicationPackageException>()),
      );
    });
  });
}
