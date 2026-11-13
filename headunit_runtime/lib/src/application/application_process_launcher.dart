import 'dart:convert';
import 'dart:io';

import 'package:headunit_runtime/headunit_runtime.dart';

/// Minimal process contract so runtime lifecycle code can be tested without
/// starting a real Windows executable.
abstract interface class ApplicationProcessHandle {
  int get pid;

  Stream<List<int>> get stdout;

  Stream<List<int>> get stderr;

  Future<int> get exitCode;

  bool kill();
}

/// Platform-specific launcher for an installed Flutter application.
abstract interface class ApplicationProcessLauncher {
  Future<ApplicationProcessHandle> launch({
    required InstalledFlutterApplication application,
    required RemoteApplicationEndpoint endpoint,
  });
}

/// Starts an installed Windows Flutter bundle as an independent process.
///
/// The one-time session endpoint is written to the child's private stdin pipe,
/// rather than its command line or inherited environment. The child reads one
/// JSON line before calling HeadunitConnection.connect().
class WindowsApplicationProcessLauncher implements ApplicationProcessLauncher {
  static const String childModeArgument = '--headunit-external-app';

  @override
  Future<ApplicationProcessHandle> launch({
    required InstalledFlutterApplication application,
    required RemoteApplicationEndpoint endpoint,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'WindowsApplicationProcessLauncher can only run on Windows.',
      );
    }

    if (application.target.platform != FlutterApplicationPlatform.windows) {
      throw UnsupportedError(
        'The installed application does not contain a Windows target.',
      );
    }

    if (endpoint.host != '127.0.0.1' ||
        endpoint.port < 1 ||
        endpoint.port > 65535 ||
        endpoint.mediaPort < 1 ||
        endpoint.mediaPort > 65535 ||
        endpoint.token.isEmpty) {
      throw ArgumentError('The child bootstrap endpoint is invalid.');
    }

    if (!await application.entryPoint.exists()) {
      throw FileSystemException(
        'The installed application executable does not exist.',
        application.entryPoint.absolute.path,
      );
    }

    final Process process = await Process.start(
      application.entryPoint.absolute.path,
      const <String>[childModeArgument],
      workingDirectory: application.bundleDirectory.absolute.path,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );

    try {
      process.stdin.writeln(
        jsonEncode(<String, Object?>{
          'host': endpoint.host,
          'port': endpoint.port,
          'mediaPort': endpoint.mediaPort,
          'token': endpoint.token,
        }),
      );
      await process.stdin.flush();
      await process.stdin.close();

      return _DartIoApplicationProcess(process);
    } catch (_) {
      process.kill();
      try {
        await process.exitCode;
      } catch (_) {
        // Preserve the original bootstrap failure.
      }
      rethrow;
    }
  }
}

class _DartIoApplicationProcess implements ApplicationProcessHandle {
  final Process _process;

  const _DartIoApplicationProcess(this._process);

  @override
  int get pid => _process.pid;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill() => _process.kill();
}
