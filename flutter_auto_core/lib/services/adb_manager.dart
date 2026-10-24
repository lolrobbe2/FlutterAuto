import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

class AdbDevice {
  final String serial;
  final String state;
  final String details;

  const AdbDevice({
    required this.serial,
    required this.state,
    required this.details,
  });

  bool get isAuthorized => state == 'device';

  @override
  String toString() {
    return '$serial [$state]${details.isEmpty ? '' : ' - $details'}';
  }
}

class AdbManager {
  static final Logger _log = Logger('AdbManager');

  late final String _localAdbDir;
  late final String _adbExecutableName;

  AdbManager() {
    final String homeDir =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';

    _localAdbDir = p.join(homeDir, '.flutter_auto_adb', 'platform-tools');
    _adbExecutableName = Platform.isWindows ? 'adb.exe' : 'adb';
  }

  /// Returns the path to the ADB executable.
  String get adbPath {
    if (_isGlobalAdbAvailable()) {
      return 'adb';
    }

    return p.join(_localAdbDir, _adbExecutableName);
  }

  /// Checks whether ADB is available on the system PATH.
  bool _isGlobalAdbAvailable() {
    try {
      final String checkCommand = Platform.isWindows ? 'where' : 'which';
      final ProcessResult result = Process.runSync(checkCommand, ['adb']);

      return result.exitCode == 0;
    } catch (error, stackTrace) {
      _log.fine('Failed to check for global ADB.', error, stackTrace);
      return false;
    }
  }

  /// Executes an ADB command and returns its result.
  Future<ProcessResult> executeCommand(
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await _ensureAdbInstalled();

    try {
      final ProcessResult result = await Process.run(
        adbPath,
        arguments,
      ).timeout(timeout);

      if (result.exitCode != 0) {
        _log.warning(
          'ADB command failed: adb ${arguments.join(' ')} '
          '(exit code: ${result.exitCode})\n${result.stderr}',
        );
      } else {
        _log.fine('ADB command succeeded: adb ${arguments.join(' ')}');
      }

      return result;
    } on IOException catch (error, stackTrace) {
      _log.severe('Failed to execute ADB command.', error, stackTrace);
      throw Exception('Failed to execute ADB: $error');
    } on Exception {
      rethrow;
    }
  }

  /// Starts the ADB server.
  Future<void> startServer() async {
    final ProcessResult result = await executeCommand(['start-server']);

    if (result.exitCode != 0) {
      throw Exception('Failed to start the ADB server: ${result.stderr}');
    }

    _log.info('ADB server started successfully.');
  }

  /// Starts a persistent ADB process with live stdout and stderr streams.
  Future<Process> startStreamingCommand(List<String> arguments) async {
    await _ensureAdbInstalled();

    try {
      _log.fine('Starting streaming ADB command: adb ${arguments.join(' ')}');
      return await Process.start(adbPath, arguments, runInShell: false);
    } on ProcessException catch (error, stackTrace) {
      _log.severe('Failed to start ADB streaming command.', error, stackTrace);
      throw Exception('Failed to start ADB streaming command: $error');
    }
  }

  /// Stops the ADB server.
  Future<void> stopServer() async {
    final ProcessResult result = await executeCommand(['kill-server']);

    if (result.exitCode != 0) {
      throw Exception('Failed to stop the ADB server: ${result.stderr}');
    }

    _log.info('ADB server stopped.');
  }

  /// Retrieves and logs all connected ADB devices.
  ///
  /// Includes devices that are unauthorized or offline.
  Future<List<AdbDevice>> listDevices() async {
    final ProcessResult result = await executeCommand(['devices', '-l']);

    if (result.exitCode != 0) {
      throw Exception('Failed to retrieve ADB devices: ${result.stderr}');
    }

    final String output = result.stdout.toString();
    final List<AdbDevice> devices = <AdbDevice>[];

    for (final String line in output.split(RegExp(r'\r?\n'))) {
      final String trimmedLine = line.trim();

      if (trimmedLine.isEmpty ||
          trimmedLine.startsWith('List of devices attached') ||
          trimmedLine.startsWith('*')) {
        continue;
      }

      final List<String> parts = trimmedLine.split(RegExp(r'\s+'));

      if (parts.length < 2) {
        continue;
      }

      devices.add(
        AdbDevice(
          serial: parts[0],
          state: parts[1],
          details: parts.length > 2 ? parts.sublist(2).join(' ') : '',
        ),
      );
    }

    _log.info('Connected ADB devices:');

    if (devices.isEmpty) {
      _log.warning('No ADB devices found.');
    } else {
      for (final AdbDevice device in devices) {
        final String status = device.isAuthorized
            ? 'AUTHORIZED'
            : device.state.toUpperCase();

        _log.info('  ${device.serial} [$status]');

        if (device.details.isNotEmpty) {
          _log.fine('    ${device.details}');
        }
      }
    }

    return devices;
  }

  /// Initializes ADB and forwards local TCP port 5277 to the device.
  Future<void> initializeAndroidAutoLink() async {
    await _ensureAdbInstalled();
    await startServer();

    final List<AdbDevice> devices = await listDevices();

    final bool hasUnauthorizedDevice = devices.any(
      (AdbDevice device) => device.state == 'unauthorized',
    );

    if (hasUnauthorizedDevice) {
      throw Exception(
        'An ADB device is unauthorized. Unlock the Android device '
        'and accept the USB or wireless debugging authorization prompt.',
      );
    }

    final bool hasAuthorizedDevice = devices.any(
      (AdbDevice device) => device.isAuthorized,
    );

    if (!hasAuthorizedDevice) {
      throw Exception(
        'No authorized ADB device found. Check the connection '
        'and enable USB or wireless debugging.',
      );
    }

    _log.info('Setting up Android Auto port forwarding...');

    final ProcessResult result = await executeCommand([
      'forward',
      'tcp:5277',
      'tcp:5277',
    ]);

    if (result.exitCode != 0) {
      throw Exception('ADB port forwarding failed: ${result.stderr}');
    }

    _log.info('ADB port forwarding is available at localhost:5277.');
  }

  /// Downloads and installs ADB if it is not already available.
  Future<void> _ensureAdbInstalled() async {
    if (_isGlobalAdbAvailable() ||
        File(p.join(_localAdbDir, _adbExecutableName)).existsSync()) {
      return;
    }

    _log.info('ADB not found. Downloading Android SDK Platform Tools...');

    final String downloadUrl = _getGoogleAdbUrl();
    final http.Response response = await http.get(Uri.parse(downloadUrl));

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download Android SDK Platform Tools: '
        'HTTP ${response.statusCode}',
      );
    }

    final Archive archive = ZipDecoder().decodeBytes(response.bodyBytes);
    final Directory targetParentDir = Directory(p.dirname(_localAdbDir));

    if (!targetParentDir.existsSync()) {
      targetParentDir.createSync(recursive: true);
    }

    for (final ArchiveFile file in archive) {
      final String filename = file.name;
      final String outputPath = p.join(targetParentDir.path, filename);

      if (file.isFile) {
        final List<int> data = file.content as List<int>;
        final File outputFile = File(outputPath);

        outputFile.parent.createSync(recursive: true);
        outputFile.writeAsBytesSync(data);
      } else {
        Directory(outputPath).createSync(recursive: true);
      }
    }

    if (!Platform.isWindows) {
      final ProcessResult chmodResult = await Process.run('chmod', [
        '+x',
        p.join(_localAdbDir, _adbExecutableName),
      ]);

      if (chmodResult.exitCode != 0) {
        throw Exception(
          'Failed to set ADB executable permissions: '
          '${chmodResult.stderr}',
        );
      }
    }

    if (!File(p.join(_localAdbDir, _adbExecutableName)).existsSync()) {
      throw Exception(
        'ADB installation failed: executable not found at $_localAdbDir',
      );
    }

    _log.info('ADB installed successfully at: $_localAdbDir');
  }

  /// Returns the official Google Platform Tools download URL.
  String _getGoogleAdbUrl() {
    if (Platform.isWindows) {
      return 'https://dl.google.com/android/repository/'
          'platform-tools-latest-windows.zip';
    } else if (Platform.isMacOS) {
      return 'https://dl.google.com/android/repository/'
          'platform-tools-latest-darwin.zip';
    } else if (Platform.isLinux) {
      return 'https://dl.google.com/android/repository/'
          'platform-tools-latest-linux.zip';
    }

    throw UnsupportedError('This operating system is not supported.');
  }
}
