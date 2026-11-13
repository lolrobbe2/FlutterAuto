import 'dart:io';

import 'package:archive/archive.dart';
import 'package:headunit_shared/headunit_shared_io.dart';

import 'flutter_application_package_reader.dart';

class InstalledFlutterApplication {
  final FlutterApplicationPackageManifest packageManifest;
  final FlutterApplicationTarget target;
  final Directory applicationDirectory;
  final Directory bundleDirectory;
  final File entryPoint;

  const InstalledFlutterApplication({
    required this.packageManifest,
    required this.target,
    required this.applicationDirectory,
    required this.bundleDirectory,
    required this.entryPoint,
  });

  ApplicationManifest get application => packageManifest.application;
}

class FlutterApplicationInstallationException implements Exception {
  final String message;
  final Object? cause;

  const FlutterApplicationInstallationException(
    this.message, {
    this.cause,
  });

  @override
  String toString() {
    if (cause == null) {
      return message;
    }

    return '$message Cause: $cause';
  }
}

class FlutterApplicationPackageInstaller {
  final FlutterApplicationPackageReader reader;

  FlutterApplicationPackageInstaller({
    FlutterApplicationPackageReader? reader,
  }) : reader = reader ?? FlutterApplicationPackageReader();

  Future<InstalledFlutterApplication> install({
    required File packageFile,
    required Directory applicationsDirectory,
    required FlutterApplicationPlatform platform,
    required String architecture,
  }) async {
    final FileSystemEntityType sourceType =
        await FileSystemEntity.type(
      packageFile.path,
      followLinks: false,
    );

    if (sourceType != FileSystemEntityType.file) {
      throw FlutterApplicationInstallationException(
        'The package source must be a regular file: ${packageFile.path}',
      );
    }

    final FileStat sourceStat = await packageFile.stat();

    if (sourceStat.size > reader.maxPackageSizeBytes) {
      throw const FlutterApplicationInstallationException(
        'The package exceeds the maximum allowed compressed size.',
      );
    }

    await applicationsDirectory.create(recursive: true);

    // Keep the archive snapshot and staging directory on the same
    // filesystem as the final installation directory.
    final Directory transactionDirectory =
        await applicationsDirectory.createTemp('.happ-install-');

    try {
      final File packageSnapshot = File(
        _join(transactionDirectory.path, 'package.happ'),
      );

      await packageFile.copy(packageSnapshot.path);

      // Validate a private snapshot instead of trusting the source file
      // to remain unchanged throughout installation.
      final FlutterApplicationPackage package =
          await reader.read(packageSnapshot);

      final FlutterApplicationTarget? target =
          package.manifest.targetFor(
        platform: platform,
        architecture: architecture,
      );

      if (target == null) {
        throw FlutterApplicationInstallationException(
          'No ${platform.wireName} target for architecture '
          '$architecture is available in '
          '${package.manifest.application.id}.',
        );
      }

      final Directory applicationDirectory = Directory(
        _join(
          applicationsDirectory.path,
          package.manifest.application.id.value,
        ),
      );

      if (await applicationDirectory.exists()) {
        throw FlutterApplicationInstallationException(
          'Application ${package.manifest.application.id} '
          'is already installed.',
        );
      }

      final Directory stagingDirectory = Directory(
        _join(transactionDirectory.path, 'application'),
      );

      await stagingDirectory.create();

      await _extractPackage(
        packageFile: packageSnapshot,
        manifest: package.manifest,
        target: target,
        destination: stagingDirectory,
      );

      final Directory bundleDirectory = Directory(
        _join(stagingDirectory.path, target.bundlePath),
      );

      final File stagedEntryPoint = File(
        _join(bundleDirectory.path, target.entryPoint),
      );

      if (!await stagedEntryPoint.exists() ||
          await stagedEntryPoint.length() == 0) {
        throw const FlutterApplicationInstallationException(
          'The extracted application entry point is missing or empty.',
        );
      }

      // Commit by renaming the complete staging directory.
      // Both directories are under applicationsDirectory.
      try {
        await stagingDirectory.rename(applicationDirectory.path);
      } on FileSystemException catch (error) {
        throw FlutterApplicationInstallationException(
          'Could not commit the application installation.',
          cause: error,
        );
      }

      final Directory installedBundleDirectory = Directory(
        _join(applicationDirectory.path, target.bundlePath),
      );

      return InstalledFlutterApplication(
        packageManifest: package.manifest,
        target: target,
        applicationDirectory: applicationDirectory,
        bundleDirectory: installedBundleDirectory,
        entryPoint: File(
          _join(installedBundleDirectory.path, target.entryPoint),
        ),
      );
    } finally {
      if (await transactionDirectory.exists()) {
        await transactionDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> _extractPackage({
    required File packageFile,
    required FlutterApplicationPackageManifest manifest,
    required FlutterApplicationTarget target,
    required Directory destination,
  }) async {
    final InputFileStream input = InputFileStream(packageFile.path);

    try {
      final Archive archive = ZipDecoder().decodeStream(
        input,
        verify: true,
        throwOnError: true,
      );

      final String bundlePrefix = '${target.bundlePath}/';
      final Set<String> extractedPaths = {};

      // Extract only the selected platform and architecture.
      for (final ArchiveFile entry in archive.files) {
        if (entry.name != target.bundlePath &&
            !entry.name.startsWith(bundlePrefix)) {
          continue;
        }

        await _extractEntry(entry, destination);

        if (entry.isFile) {
          extractedPaths.add(entry.name);
        }
      }

      // The icon is shared application metadata, not necessarily
      // part of the platform-specific runtime bundle.
      final String? iconPath = manifest.application.iconPath;

      if (iconPath != null && !extractedPaths.contains(iconPath)) {
        ArchiveFile? iconEntry;

        for (final ArchiveFile entry in archive.files) {
          if (entry.name == iconPath) {
            iconEntry = entry;
            break;
          }
        }

        if (iconEntry == null || !iconEntry.isFile) {
          throw FlutterApplicationInstallationException(
            'The application icon is missing: $iconPath',
          );
        }

        await _extractEntry(iconEntry, destination);
      }
    } on ArchiveException catch (error) {
      throw FlutterApplicationInstallationException(
        'Could not decode the HAPP archive during installation.',
        cause: error,
      );
    } finally {
      await input.close();
    }
  }

  Future<void> _extractEntry(
    ArchiveFile entry,
    Directory destination,
  ) async {
    if (entry.isSymbolicLink) {
      throw FlutterApplicationInstallationException(
        'Symbolic links are not allowed: ${entry.name}',
      );
    }

    String relativePath = entry.name;

    if (relativePath.endsWith('/')) {
      relativePath = relativePath.substring(
        0,
        relativePath.length - 1,
      );
    }

    if (relativePath.isEmpty) {
      return;
    }

    _validateRelativePath(relativePath);

    final String outputPath = _join(
      destination.path,
      relativePath,
    );

    if (!entry.isFile) {
      await Directory(outputPath).create(recursive: true);
      return;
    }

    final List<int>? bytes;

    try {
      bytes = entry.readBytes();
    } on ArchiveException catch (error) {
      throw FlutterApplicationInstallationException(
        'Could not extract archive entry: ${entry.name}',
        cause: error,
      );
    }

    if (bytes == null || bytes.length != entry.size) {
      throw FlutterApplicationInstallationException(
        'Extracted entry has an invalid size: ${entry.name}',
      );
    }

    final File outputFile = File(outputPath);

    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsBytes(bytes, flush: true);
  }

  void _validateRelativePath(String path) {
    final List<String> segments = path.split('/');

    if (path.startsWith('/') ||
        path.contains('\\') ||
        path.contains(':') ||
        segments.any(
          (String segment) =>
              segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw FlutterApplicationInstallationException(
        'Unsafe extraction path: $path',
      );
    }
  }

  String _join(String base, String relative) {
    final List<String> segments = relative.split('/');

    return <String>[
      base,
      ...segments,
    ].join(Platform.pathSeparator);
  }
}