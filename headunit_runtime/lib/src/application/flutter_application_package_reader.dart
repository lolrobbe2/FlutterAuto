import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:headunit_shared/headunit_shared_io.dart';

class FlutterApplicationPackage {
  final File sourceFile;
  final FlutterApplicationPackageManifest manifest;
  final int archiveSizeBytes;

  const FlutterApplicationPackage({
    required this.sourceFile,
    required this.manifest,
    required this.archiveSizeBytes,
  });
}

class FlutterApplicationPackageException implements Exception {
  final String message;
  final Object? cause;

  const FlutterApplicationPackageException(
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

class FlutterApplicationPackageReader {
  static const int defaultMaxPackageSizeBytes = 1024 * 1024 * 1024;
  static const int defaultMaxExpandedSizeBytes = 2 * 1024 * 1024 * 1024;
  static const int defaultMaxManifestSizeBytes = 1024 * 1024;
  static const int defaultMaxArchiveEntries = 20000;

  static final RegExp _invalidWindowsCharacters = RegExp(
    r'[<>:"\\|?*\x00-\x1F]',
  );

  static final RegExp _reservedWindowsName = RegExp(
    r'^(CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|CLOCK\$|COM[1-9]|LPT[1-9])$',
    caseSensitive: false,
  );

  final int maxPackageSizeBytes;
  final int maxExpandedSizeBytes;
  final int maxManifestSizeBytes;
  final int maxArchiveEntries;

  FlutterApplicationPackageReader({
    this.maxPackageSizeBytes = defaultMaxPackageSizeBytes,
    this.maxExpandedSizeBytes = defaultMaxExpandedSizeBytes,
    this.maxManifestSizeBytes = defaultMaxManifestSizeBytes,
    this.maxArchiveEntries = defaultMaxArchiveEntries,
  }) {
    if (maxPackageSizeBytes <= 0 ||
        maxExpandedSizeBytes <= 0 ||
        maxManifestSizeBytes <= 0 ||
        maxArchiveEntries <= 0) {
      throw ArgumentError('Package reader limits must be greater than zero.');
    }
  }

  Future<FlutterApplicationPackage> read(File packageFile) async {
    if (!packageFile.path.toLowerCase().endsWith('.happ')) {
      throw const FlutterApplicationPackageException(
        'Flutter application package must use the .happ extension.',
      );
    }

    final FileStat fileStat = await packageFile.stat();

    if (fileStat.type != FileSystemEntityType.file) {
      throw FlutterApplicationPackageException(
        'Package is not a regular file: ${packageFile.path}',
      );
    }

    if (fileStat.size > maxPackageSizeBytes) {
      throw const FlutterApplicationPackageException(
        'Package exceeds the maximum compressed size.',
      );
    }

    final InputFileStream input = InputFileStream(packageFile.path);

    try {
      final Archive archive;

      try {
        archive = ZipDecoder().decodeStream(
          input,
          verify: true,
          throwOnError: true,
        );
      } on ArchiveException catch (error) {
        throw FlutterApplicationPackageException(
          'The HAPP file is not a valid ZIP archive.',
          cause: error,
        );
      }

      final Map<String, ArchiveFile> entries = _validateArchive(archive);

      final ArchiveFile? manifestEntry = entries['manifest.json'];

      if (manifestEntry == null || !manifestEntry.isFile) {
        throw const FlutterApplicationPackageException(
          'The package must contain a manifest.json file at its root.',
        );
      }

      if (manifestEntry.size > maxManifestSizeBytes) {
        throw const FlutterApplicationPackageException(
          'manifest.json exceeds the maximum allowed size.',
        );
      }

      final List<int>? manifestBytes;

      try {
        manifestBytes = manifestEntry.readBytes();
      } on ArchiveException catch (error) {
        throw FlutterApplicationPackageException(
          'Could not read manifest.json.',
          cause: error,
        );
      }

      if (manifestBytes == null ||
          manifestBytes.length > maxManifestSizeBytes) {
        throw const FlutterApplicationPackageException(
          'Could not read a valid manifest.json.',
        );
      }

      final FlutterApplicationPackageManifest manifest =
          _parseManifest(manifestBytes);

      _validateManifestReferences(manifest, entries);

      return FlutterApplicationPackage(
        sourceFile: packageFile,
        manifest: manifest,
        archiveSizeBytes: fileStat.size,
      );
    } finally {
      await input.close();
    }
  }

  Map<String, ArchiveFile> _validateArchive(Archive archive) {
    if (archive.files.isEmpty) {
      throw const FlutterApplicationPackageException(
        'The HAPP archive is empty.',
      );
    }

    if (archive.files.length > maxArchiveEntries) {
      throw const FlutterApplicationPackageException(
        'The HAPP archive contains too many entries.',
      );
    }

    final Map<String, ArchiveFile> entries = {};
    final Map<String, String> portablePaths = {};
    final Set<String> pathsWithDescendants = {};

    int expandedSize = 0;

    for (final ArchiveFile entry in archive.files) {
      if (entry.isSymbolicLink) {
        throw FlutterApplicationPackageException(
          'Symbolic links are not permitted in HAPP packages: ${entry.name}',
        );
      }

      final String path = _normalizeArchivePath(entry);

      final String portablePath = path.toLowerCase();
      final String? existingPath = portablePaths[portablePath];

      if (existingPath != null) {
        throw FlutterApplicationPackageException(
          'Duplicate or case-insensitive duplicate archive paths: '
          '$existingPath and $path',
        );
      }

      portablePaths[portablePath] = path;
      entries[path] = entry;

      if (entry.size < 0) {
        throw FlutterApplicationPackageException(
          'Archive entry has an invalid size: $path',
        );
      }

      if (entry.isFile) {
        if (entry.size > maxExpandedSizeBytes - expandedSize) {
          throw const FlutterApplicationPackageException(
            'The expanded HAPP archive exceeds the maximum allowed size.',
          );
        }

        expandedSize += entry.size;
      }

      final List<String> segments = path.split('/');
      String parent = '';

      for (int index = 0; index < segments.length - 1; index++) {
        parent = parent.isEmpty
            ? segments[index]
            : '$parent/${segments[index]}';

        pathsWithDescendants.add(parent);
      }
    }

    for (final MapEntry<String, ArchiveFile> item in entries.entries) {
      final List<String> segments = item.key.split('/');
      String parent = '';

      for (int index = 0; index < segments.length - 1; index++) {
        parent = parent.isEmpty
            ? segments[index]
            : '$parent/${segments[index]}';

        if (entries[parent]?.isFile ?? false) {
          throw FlutterApplicationPackageException(
            'An archive file is also being used as a directory: $parent',
          );
        }
      }

      if (item.value.isFile &&
          pathsWithDescendants.contains(item.key)) {
        throw FlutterApplicationPackageException(
          'An archive file cannot contain child entries: ${item.key}',
        );
      }
    }

    return entries;
  }

  String _normalizeArchivePath(ArchiveFile entry) {
    String path = entry.name;

    if (path.endsWith('/')) {
      if (entry.isFile) {
        throw FlutterApplicationPackageException(
          'A file entry cannot end with a directory separator: $path',
        );
      }

      path = path.substring(0, path.length - 1);
    }

    if (path.isEmpty || path.startsWith('/') || path.contains('\\')) {
      throw FlutterApplicationPackageException(
        'Invalid archive path: ${entry.name}',
      );
    }

    final List<String> segments = path.split('/');

    for (final String segment in segments) {
      if (segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment != segment.trim() ||
          segment.endsWith('.') ||
          segment.endsWith(' ') ||
          _invalidWindowsCharacters.hasMatch(segment)) {
        throw FlutterApplicationPackageException(
          'Unsafe archive path: ${entry.name}',
        );
      }

      final String deviceName = segment.split('.').first;

      if (_reservedWindowsName.hasMatch(deviceName)) {
        throw FlutterApplicationPackageException(
          'Archive path uses a reserved Windows name: ${entry.name}',
        );
      }
    }

    return path;
  }

  FlutterApplicationPackageManifest _parseManifest(
    List<int> bytes,
  ) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(bytes));

      if (decoded is! Map) {
        throw const FormatException(
          'The manifest root must be a JSON object.',
        );
      }

      final Map<String, Object?> json = {};

      for (final Object? key in decoded.keys) {
        if (key is! String) {
          throw const FormatException(
            'The manifest contains a non-string key.',
          );
        }

        json[key] = decoded[key];
      }

      return FlutterApplicationPackageManifest.fromJson(json);
    } on FormatException catch (error) {
      throw FlutterApplicationPackageException(
        'Invalid HAPP manifest.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw FlutterApplicationPackageException(
        'HAPP manifest validation failed.',
        cause: error,
      );
    }
  }

  void _validateManifestReferences(
    FlutterApplicationPackageManifest manifest,
    Map<String, ArchiveFile> entries,
  ) {
    final String? iconPath = manifest.application.iconPath;

    if (iconPath != null) {
      _requireFile(
        entries,
        iconPath,
        'Application icon',
      );
    }

    for (final FlutterApplicationTarget target in manifest.targets) {
      final String executablePath =
          '${target.bundlePath}/${target.entryPoint}';

      _requireFile(
        entries,
        executablePath,
        '${target.platform.wireName} ${target.architecture} entry point',
      );
    }
  }

  void _requireFile(
    Map<String, ArchiveFile> entries,
    String path,
    String description,
  ) {
    final ArchiveFile? entry = entries[path];

    if (entry == null || !entry.isFile) {
      throw FlutterApplicationPackageException(
        '$description does not exist in the HAPP archive: $path',
      );
    }
  }
}