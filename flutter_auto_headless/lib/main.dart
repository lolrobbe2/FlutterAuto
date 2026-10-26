import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_auto_core/branding/flutter_auto_splash_screen.dart';
import 'package:flutter_auto_core/flutter_auto_core.dart';
import 'package:logging/logging.dart';
import 'package:window_manager/window_manager.dart';

import 'headunit_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fullscreen the desktop window before displaying the app.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setFullScreen(true);
  }

  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    debugPrint(
      '[${record.level.name}] ${record.loggerName}: ${record.message}',
    );

    if (record.error != null) {
      debugPrint('Error: ${record.error}');
    }
  });

  runApp(const HeadunitApp());
}

typedef ConnectionFailureCallback = Future<void> Function(
  HeadunitSession session,
  Object error,
  StackTrace stackTrace,
);

class HeadunitApp extends StatefulWidget {
  const HeadunitApp({super.key});

  @override
  State<HeadunitApp> createState() => _HeadunitAppState();
}

class _HeadunitAppState extends State<HeadunitApp> {
  final Logger _log = Logger('HeadunitApp');
  final AdbManager _adbManager = AdbManager();

  HeadunitSession? _session;
  String? _deviceSerial;
  String? _error;
  bool _usingUsb = false;
  bool _starting = true;
  String? _selectedAdbSerial;

  @override
  void initState() {
    super.initState();
    unawaited(_startProjection());
  }

  Future<HeadunitSession> _createAdbSession() async {
    _log.info('Starting ADB server...');
    await _adbManager.startServer();

    _log.info('Searching for authorized ADB devices...');
    final devices = await _adbManager.listDevices();

    final authorized = devices.where((device) => device.isAuthorized).toList();

    if (authorized.isEmpty) {
      throw StateError(
        'USB connection failed and no authorized ADB device was found. '
        'Check that the phone is visible in "adb devices -l" and that '
        'USB debugging is authorized.',
      );
    }

    final device = authorized.first;
    _log.info('Selected ADB device: ${device.serial}');

    final result = await _adbManager.executeCommand([
      '-s',
      device.serial,
      'forward',
      'tcp:5277',
      'tcp:5277',
    ]);

    if (result.exitCode != 0) {
      throw StateError('ADB port forwarding failed: ${result.stderr}');
    }

    try {
      final session = HeadunitSession.adb(
        adbManager: _adbManager,
        host: InternetAddress.loopbackIPv4.address,
        port: 5277,
        configureAdb: false,
        videoResolution: VideoResolution_Enum.VIDEO_800x480,
      );

      _selectedAdbSerial = device.serial;
      return session;
    } catch (_) {
      await _removePortForward(device.serial);
      rethrow;
    }
  }

  Future<void> _startProjection() async {
    HeadunitSession? session;
    String? selectedSerial;
    bool usingUsb = false;

    try {
      // 1. Try native USB transport first.
      _log.info('Trying Android Auto over USB...');

      try {
        session = HeadunitSession.usb(
          adbManager: _adbManager,
          videoResolution: VideoResolution_Enum.VIDEO_800x480,
        );

        // The session connector will call connect() after the screen builds.
        // Establish the USB transport inside connect(), not here.
        usingUsb = true;
        _log.info('USB session created.');
      } catch (error, stackTrace) {
        _log.warning(
          'Could not create USB session; falling back to ADB.',
          error,
          stackTrace,
        );

        await session?.dispose();
        session = null;
      }

      // Note: HeadunitSession.usb() creates a session before it actually
      // opens USB. If USB opening fails during session.connect(), the
      // connector below handles the fallback.
      if (session == null) {
        session = await _createAdbSession();
        selectedSerial = _selectedAdbSerial;
      }

      if (!mounted) {
        await session.dispose();
        if (selectedSerial != null) {
          await _removePortForward(selectedSerial);
        }
        return;
      }

      setState(() {
        _session = session;
        _deviceSerial = selectedSerial ?? (usingUsb ? 'USB' : null);
        _usingUsb = usingUsb;
        _starting = false;
      });
    } catch (error, stackTrace) {
      _log.severe(
        'Failed to start Android Auto projection.',
        error,
        stackTrace,
      );

      await session?.dispose();

      if (selectedSerial != null) {
        await _removePortForward(selectedSerial);
      }

      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _starting = false;
      });
    }
  }

  Future<void> _removePortForward(String serial) async {
    try {
      await _adbManager.executeCommand([
        '-s',
        serial,
        'forward',
        '--remove',
        'tcp:5277',
      ]);
      _log.info('Removed port forwarding for $serial.');
    } catch (error, stackTrace) {
      _log.warning(
        'Could not remove port forwarding for $serial.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _handleConnectionFailure(
    HeadunitSession failedSession,
    Object error,
    StackTrace stackTrace,
  ) async {
    // Ignore failures from a session that is no longer active.
    if (!mounted || !identical(_session, failedSession)) return;

    final bool failedOverUsb = _usingUsb;
    final String? failedSerial = !failedOverUsb && _deviceSerial != 'USB'
        ? _deviceSerial
        : null;

    _log.warning(
      '${failedOverUsb ? 'USB' : 'ADB'} connection failed.',
      error,
      stackTrace,
    );

    // Show the loading screen and remove the failed connector immediately.
    setState(() {
      _session = null;
      _deviceSerial = null;
      _usingUsb = false;
      _starting = true;
      _error = null;
    });

    try {
      await failedSession.dispose();
    } catch (disposeError, disposeStack) {
      _log.warning(
        'Failed to dispose the failed session.',
        disposeError,
        disposeStack,
      );
    }

    // If ADB itself failed, report the error instead of retrying ADB forever.
    if (!failedOverUsb) {
      if (failedSerial != null) {
        await _removePortForward(failedSerial);
      }

      if (!mounted) return;

      setState(() {
        _error = 'ADB connection failed:\n$error';
        _starting = false;
      });
      return;
    }

    // USB failed: now start ADB and create a completely new session.
    try {
      _log.warning('Falling back from direct USB to ADB.');

      _selectedAdbSerial = null;
      final fallbackSession = await _createAdbSession();
      final serial = _selectedAdbSerial;

      if (serial == null) {
        await fallbackSession.dispose();
        throw StateError(
          'ADB session was created, but no device serial was recorded.',
        );
      }

      if (!mounted) {
        await fallbackSession.dispose();
        await _removePortForward(serial);
        return;
      }

      setState(() {
        _session = fallbackSession;
        _deviceSerial = serial;
        _usingUsb = false;
        _starting = false;
        _error = null;
      });

      _log.info(
        'ADB fallback session created for $serial. '
        'The replacement screen will now connect.',
      );
    } catch (fallbackError, fallbackStack) {
      _log.severe('ADB fallback failed.', fallbackError, fallbackStack);

      final serial = _selectedAdbSerial;
      if (serial != null) {
        await _removePortForward(serial);
      }

      if (!mounted) return;

      setState(() {
        _error =
            'USB connection failed:\n$error\n\n'
            'ADB fallback also failed:\n$fallbackError';
        _starting = false;
      });
    }
  }

  Future<void> _disposeResources() async {
    final session = _session;
    final serial = _deviceSerial;
    final usingUsb = _usingUsb;

    if (session != null) {
      try {
        await session.dispose();
      } catch (error, stackTrace) {
        _log.warning(
          'Failed to dispose the headunit session.',
          error,
          stackTrace,
        );
      }
    }

    // Never try to remove an ADB forward for the placeholder serial "USB".
    if (!usingUsb && serial != null && serial != 'USB') {
      await _removePortForward(serial);
    }
  }

  @override
  void dispose() {
    unawaited(_disposeResources());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Auto',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    // Keep the branded splash visible while creating or connecting a session.
    if (_starting) {
      return const FlutterAutoSplashScreen();
    }

    // Connection/startup errors remain in the logs; do not replace the splash
    // with a separate text-based status/error screen.
    if (_error != null) {
      return const FlutterAutoSplashScreen();
    }

    final HeadunitSession? session = _session;
    final String? serial = _deviceSerial;

    if (session == null || serial == null) {
      return const FlutterAutoSplashScreen();
    }

    return _SessionConnector(
      key: ValueKey('${_usingUsb ? 'usb' : 'adb'}:$serial'),
      deviceSerial: serial,
      session: session,
      onConnectionFailed: _handleConnectionFailure,
    );
  }
}

/// Connect only after the HeadunitScreen has had its first frame to
/// initialize its decoder and input handling.
class _SessionConnector extends StatefulWidget {
  const _SessionConnector({
    super.key,
    required this.deviceSerial,
    required this.session,
    required this.onConnectionFailed,
  });

  final String deviceSerial;
  final HeadunitSession session;
  final ConnectionFailureCallback onConnectionFailed;

  @override
  State<_SessionConnector> createState() => _SessionConnectorState();
}

class _SessionConnectorState extends State<_SessionConnector> {
  final Logger _log = Logger('SessionConnector');

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_connect());
      }
    });
  }

  Future<void> _connect() async {
    try {
      _log.info('Connecting headunit session for ${widget.deviceSerial}...');

      await widget.session.connect();

      _log.info('Headunit session connected using ${widget.deviceSerial}.');
    } catch (error, stackTrace) {
      _log.warning(
        'Connection failed for ${widget.deviceSerial}.',
        error,
        stackTrace,
      );

      if (!mounted) return;

      await widget.onConnectionFailed(widget.session, error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HeadunitScreen(
      deviceSerial: widget.deviceSerial,
      session: widget.session,
      videoBuilder: (context, decoder) {
        return FfmpegVideoView(
          decoder: decoder,
          splashScreen: const FlutterAutoSplashScreen(),
        );
      },
    );
  }
}

