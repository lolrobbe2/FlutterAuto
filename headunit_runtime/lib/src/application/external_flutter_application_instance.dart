import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

import 'application_process_launcher.dart';
import 'flutter_application_package_installer.dart';
import 'remote_application_rpc_session.dart';

/// An [ApplicationInstance] whose UI and Flutter engine run in another process.
///
/// The instance owns the child process, authenticated RPC session, accepted
/// media connection, and process-exit monitor. It deliberately does not own
/// the RemoteVideoSurface widget; the shell owns that presentation.
class ExternalFlutterApplicationInstance implements ApplicationInstance {
  @override
  final ApplicationId id;
  final ApplicationLaunchContext _context;
  final RemoteServiceBroker _serviceBroker;
  final InstalledFlutterApplication _installedApplication;
  final ApplicationProcessLauncher _processLauncher;
  final VideoStreamConfiguration _mediaConfiguration;
  final Duration _startupTimeout;
  final Duration _gracefulShutdownTimeout;
  final Duration _killTimeout;

  final StreamController<ApplicationLifecycleEvent> _events =
      StreamController<ApplicationLifecycleEvent>.broadcast();
  final ValueNotifier<MediaStreamConnection?> _mediaConnection =
      ValueNotifier<MediaStreamConnection?>(null);
  final ValueNotifier<HeadunitUiPage?> _uiPage = ValueNotifier<HeadunitUiPage?>(
    null,
  );

  ApplicationLifecycleState _state = ApplicationLifecycleState.stopped;
  RemoteApplicationRpcSession? _session;
  ApplicationProcessHandle? _process;
  StreamSubscription<MediaStreamConnection>? _mediaSubscription;
  StreamSubscription<HeadunitUiPage?>? _uiSubscription;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Future<void>? _releaseFuture;
  Future<void>? _stopFuture;
  bool _stopRequested = false;

  ExternalFlutterApplicationInstance({
    required this.id,
    required ApplicationLaunchContext context,
    required RemoteServiceBroker serviceBroker,
    required InstalledFlutterApplication installedApplication,
    required this._processLauncher,
    this._mediaConfiguration = VideoStreamConfiguration.defaultConfiguration,
    this._startupTimeout = const Duration(seconds: 10),
    this._gracefulShutdownTimeout = const Duration(seconds: 2),
    this._killTimeout = const Duration(seconds: 2),
  }) : _context = context,
       _serviceBroker = serviceBroker,
       _installedApplication = installedApplication {
    if (context.applicationId != id || serviceBroker.applicationId != id) {
      throw ArgumentError(
        'External application context and service broker must match $id.',
      );
    }
    if (installedApplication.application.id != id) {
      throw ArgumentError(
        'Installed package identity does not match application $id.',
      );
    }
  }

  @override
  ApplicationLifecycleState get state => _state;

  @override
  Stream<ApplicationLifecycleEvent> get lifecycleEvents => _events.stream;

  /// A nullable listenable because the child can authenticate before it opens
  /// the compressed-video channel.
  ValueListenable<MediaStreamConnection?> get mediaConnection =>
      _mediaConnection;

  /// Current standard UI page published by the external process.
  ValueListenable<HeadunitUiPage?> get uiPage => _uiPage;

  int? get processId => _process?.pid;

  bool get isProcessRunning => _process != null;

  @override
  Future<void> start() async {
    if (_state != ApplicationLifecycleState.stopped) {
      throw StateError('Cannot start $id from ${_state.name}.');
    }

    _transition(ApplicationLifecycleState.starting);

    try {
      final RemoteApplicationRpcSession session =
          await RemoteApplicationRpcSession.bind(
            context: _context,
            serviceBroker: _serviceBroker,
            mediaConfiguration: _mediaConfiguration,
          );
      _session = session;

      // Subscribe before launching the child so its first media connection
      // cannot be missed.
      _mediaSubscription = session.mediaConnections.listen((
        MediaStreamConnection connection,
      ) {
        if (_state == ApplicationLifecycleState.stopping ||
            _state == ApplicationLifecycleState.stopped ||
            _state == ApplicationLifecycleState.failed) {
          return;
        }
        _mediaConnection.value = connection;
      });

      _uiSubscription = session.uiChannel.pages.listen((HeadunitUiPage? page) {
        if (_state != ApplicationLifecycleState.stopping &&
            _state != ApplicationLifecycleState.stopped &&
            _state != ApplicationLifecycleState.failed) {
          _uiPage.value = page;
        }
      });
      _uiPage.value = session.uiChannel.currentPage;

      final ApplicationProcessHandle process = await _processLauncher.launch(
        application: _installedApplication,
        endpoint: session.endpoint,
      );
      _process = process;

      // Always drain both pipes. A child that logs heavily must not block on a
      // full OS pipe while the headunit waits for authentication.
      _stdoutSubscription = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((String output) {
            if (output.isNotEmpty) {
              print('[$id stdout] $output');
            }
          });
      _stderrSubscription = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((String output) {
            if (output.isNotEmpty) {
              print('[$id stderr] $output');
            }
          });

      unawaited(_monitorProcess(process));

      await Future.any<void>(<Future<void>>[
        session.waitUntilAuthenticated(timeout: _startupTimeout),
        process.exitCode.then<void>((int code) {
          throw StateError(
            'External application $id exited with code $code before '
            'authenticating its control connection.',
          );
        }),
      ]).timeout(_startupTimeout);

      if (_state == ApplicationLifecycleState.failed) {
        throw StateError('External application $id exited during startup.');
      }

      session.sendLifecycleState(ApplicationLifecycleState.background);
      _transition(ApplicationLifecycleState.background);
    } catch (error) {
      if (_state.canTransitionTo(ApplicationLifecycleState.failed)) {
        _transition(ApplicationLifecycleState.failed, reason: error.toString());
      }

      final ApplicationProcessHandle? process = _process;
      if (process != null) {
        process.kill();
        try {
          await process.exitCode.timeout(_killTimeout);
        } catch (_) {
          // Startup is already failing; still release the IPC/media endpoints.
        }
      }
      _process = null;
      await _releaseResources();
      rethrow;
    }
  }

  Future<void> _monitorProcess(ApplicationProcessHandle process) async {
    final int exitCode = await process.exitCode;
    if (identical(_process, process)) {
      _process = null;
    }

    if (_stopRequested ||
        _state == ApplicationLifecycleState.stopping ||
        _state == ApplicationLifecycleState.stopped) {
      return;
    }

    if (_state.canTransitionTo(ApplicationLifecycleState.failed)) {
      _transition(
        ApplicationLifecycleState.failed,
        reason: 'The external process exited with code $exitCode.',
      );
    }

    try {
      await _releaseResources();
    } catch (error) {
      print('[$id] Failed to release the external application session: $error');
    }
  }

  Future<void> _releaseResources() {
    final Future<void>? existing = _releaseFuture;
    if (existing != null) {
      return existing;
    }

    final Future<void> operation = _releaseResourcesInternal();
    _releaseFuture = operation;
    return operation;
  }

  Future<void> _releaseResourcesInternal() async {
    await _mediaSubscription?.cancel();
    _mediaSubscription = null;
    _mediaConnection.value = null;
    await _uiSubscription?.cancel();
    _uiSubscription = null;
    _uiPage.value = null;

    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;

    final RemoteApplicationRpcSession? session = _session;
    _session = null;
    await session?.dispose();
  }

  void sendPointerEvent(ApplicationPointerEvent event) {
    _session?.sendPointerEvent(event);
  }

  /// Invokes an action from the external application's current UI page.
  void sendUiAction(String actionId) {
    _session?.sendUiAction(actionId);
  }

  @override
  Future<void> setForeground() async {
    _ensureState(ApplicationLifecycleState.background);
    _session?.sendLifecycleState(ApplicationLifecycleState.foreground);
    _transition(ApplicationLifecycleState.foreground);
  }

  @override
  Future<void> setBackground() async {
    _ensureState(ApplicationLifecycleState.foreground);
    _session?.sendLifecycleState(ApplicationLifecycleState.background);
    _transition(ApplicationLifecycleState.background);
  }

  @override
  Future<void> suspend() async {
    _ensureState(ApplicationLifecycleState.background);
    _session?.sendLifecycleState(ApplicationLifecycleState.suspended);
    _transition(ApplicationLifecycleState.suspended);
  }

  @override
  Future<void> resume() async {
    _ensureState(ApplicationLifecycleState.suspended);
    _session?.sendLifecycleState(ApplicationLifecycleState.background);
    _transition(ApplicationLifecycleState.background);
  }

  @override
  Future<void> stop() {
    final Future<void>? existing = _stopFuture;
    if (existing != null) {
      return existing;
    }
    if (_state == ApplicationLifecycleState.stopped) {
      return Future<void>.value();
    }

    final Future<void> operation = _stopInternal();
    _stopFuture = operation;
    return operation;
  }

  Future<void> _stopInternal() async {
    _stopRequested = true;

    if (_state != ApplicationLifecycleState.failed &&
        _state != ApplicationLifecycleState.stopping) {
      _transition(ApplicationLifecycleState.stopping);
    }

    _session?.sendLifecycleState(ApplicationLifecycleState.stopping);

    Object? firstError;
    StackTrace? firstStackTrace;

    final ApplicationProcessHandle? process = _process;
    if (process != null) {
      try {
        await process.exitCode.timeout(_gracefulShutdownTimeout);
      } on TimeoutException {
        process.kill();
        try {
          await process.exitCode.timeout(_killTimeout);
        } catch (error, stackTrace) {
          firstError = error;
          firstStackTrace = stackTrace;
        }
      } catch (error, stackTrace) {
        firstError = error;
        firstStackTrace = stackTrace;
      }
    }

    _process = null;

    try {
      await _releaseResources();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    if (_state != ApplicationLifecycleState.stopped &&
        _state.canTransitionTo(ApplicationLifecycleState.stopped)) {
      _transition(ApplicationLifecycleState.stopped);
    }

    await _events.close();

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  void _transition(ApplicationLifecycleState next, {String? reason}) {
    if (!_state.canTransitionTo(next)) {
      throw StateError(
        'Invalid lifecycle transition for $id: ${_state.name} -> ${next.name}.',
      );
    }

    final ApplicationLifecycleState previous = _state;
    _state = next;
    _events.add(
      ApplicationLifecycleEvent(
        applicationId: id,
        previousState: previous,
        currentState: next,
        timestamp: DateTime.now(),
        reason: reason,
      ),
    );
  }

  void _ensureState(ApplicationLifecycleState expected) {
    if (_state != expected) {
      throw StateError(
        'Application $id is ${_state.name}; expected ${expected.name}.',
      );
    }
  }
}
