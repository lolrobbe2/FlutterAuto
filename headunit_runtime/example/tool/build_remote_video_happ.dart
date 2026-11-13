import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

const String _applicationId = 'com.example.remote_video_demo';
const String _bundlePath = 'artifacts/windows/x64';
const String _executableName = 'example.exe';

Future<void> main() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('This demo package is a Windows target.');
  }

  final Directory releaseBundle = Directory(
    'build/windows/x64/runner/Release',
  );
  final File executable = File(
    '${releaseBundle.path}${Platform.pathSeparator}$_executableName',
  );

  if (!await executable.exists()) {
    throw StateError(
      'Windows release executable not found at ${executable.path}. '
      'Run "flutter build windows --release" first.',
    );
  }

  // Keep this packager independent of Flutter libraries so it can be executed
  // by the standalone Dart VM. These fields match the HAPP manifest schema.
  final Map<String, Object?> manifest = <String, Object?>{
    'formatVersion': 1,
    'application': <String, Object?>{
      'schemaVersion': 1,
      'id': _applicationId,
      'name': 'Remote Video Demo',
      'version': '1.0.0',
      'minimumFrameworkVersion': '0.1.0',
      'runtime': 'flutter',
      'entryPoint': null,
      'iconPath': null,
      'description': null,
      'requestedCapabilities': <String>[],
    },
    'targets': <Map<String, Object?>>[
      <String, Object?>{
        'platform': 'windows',
        'architecture': 'x64',
        'bundlePath': _bundlePath,
        'entryPoint': _executableName,
      },
    ],
  };

  final Archive archive = Archive();
  final List<int> manifestBytes = utf8.encode(jsonEncode(manifest));
  archive.addFile(
    ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
  );

  await for (final FileSystemEntity entity in releaseBundle.list(
    recursive: true,
    followLinks: false,
  )) {
    final FileSystemEntityType type = await FileSystemEntity.type(
      entity.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link) {
      throw StateError('Symbolic links are not packaged: ${entity.path}');
    }
    if (type != FileSystemEntityType.file) {
      continue;
    }

    final String relativePath = entity.path
        .substring(releaseBundle.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    final List<int> bytes = await File(entity.path).readAsBytes();
    archive.addFile(
      ArchiveFile('$_bundlePath/$relativePath', bytes.length, bytes),
    );
  }

  final List<int> packageBytes = ZipEncoder().encode(archive);
  final Directory outputDirectory = Directory('build');
  await outputDirectory.create(recursive: true);
  final File output = File(
    '${outputDirectory.path}${Platform.pathSeparator}remote_video_demo.happ',
  );
  await output.writeAsBytes(packageBytes, flush: true);

  stdout.writeln('Created ${output.absolute.path}');
}
