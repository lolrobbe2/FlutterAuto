import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
      throw Exception(
        'USB connection failed and no authorized ADB device was found.',
      );
    }

    final device = authorized.first;
    _selectedAdbSerial = device.serial;

    _log.info('Selected ADB device: ${device.serial}');

    final result = await _adbManager.executeCommand([
      '-s',
      device.serial,
      'forward',
      'tcp:5277',
      'tcp:5277',
    ]);

    if (result.exitCode != 0) {
      throw Exception('ADB port forwarding failed: ${result.stderr}');
    }

    return HeadunitSession.adb(
      adbManager: _adbManager,
      host: InternetAddress.loopbackIPv4.address,
      port: 5277,
      configureAdb: false,
      videoResolution: VideoResolution_Enum.VIDEO_800x480,
    );
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

  Future<void> _disposeResources() async {
    final HeadunitSession? session = _session;
    final String? serial = _deviceSerial;

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

    if (serial != null) {
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
    if (_starting) {
      return const _StatusScreen(
        message: 'Connecting to Android Auto...',
        showProgress: true,
      );
    }

    if (_error != null) {
      return _StatusScreen(
        message: 'Unable to start Android Auto',
        details: _error,
        showProgress: false,
      );
    }

    final HeadunitSession? session = _session;
    final String? serial = _deviceSerial;

    if (session == null || serial == null) {
      return const _StatusScreen(
        message: 'No Android Auto session available.',
        showProgress: false,
      );
    }

    return _SessionConnector(
      key: ValueKey(serial),
      deviceSerial: serial,
      session: session,
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
  });

  final String deviceSerial;
  final HeadunitSession session;

  @override
  State<_SessionConnector> createState() => _SessionConnectorState();
}

class _SessionConnectorState extends State<_SessionConnector> {
  final Logger _log = Logger('SessionConnector');
  String? _connectionError;

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
      _log.info('Headunit session connected.');
    } catch (error, stackTrace) {
      _log.warning(
        'Initial connection failed; attempting ADB fallback.',
        error,
        stackTrace,
      );

      if (!mounted) return;

      // A USB session failed. Ask the parent app to perform the ADB fallback.
      if (widget.deviceSerial == 'USB') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const _StatusScreen(
              message: 'USB connection failed',
              details: 'Restarting with ADB fallback is required.',
              showProgress: false,
            ),
          ),
        );
        return;
      }

      setState(() {
        _connectionError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_connectionError != null) {
      return _StatusScreen(
        message: 'Failed to connect to Android Auto',
        details: _connectionError,
        showProgress: false,
      );
    }

    return HeadunitScreen(
      deviceSerial: widget.deviceSerial,
      session: widget.session,
      videoBuilder: (context, decoder) {
        return FfmpegVideoView(decoder: decoder);
      },
    );
  }
}

class _StatusScreen extends StatelessWidget {
  const _StatusScreen({
    required this.message,
    required this.showProgress,
    this.details,
  });

  final String message;
  final String? details;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showProgress) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                ],
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
                if (details != null) ...[
                  const SizedBox(height: 16),
                  SelectableText(
                    details!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
