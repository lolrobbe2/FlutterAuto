import 'package:headunit_shared/headunit_shared_io.dart';

import 'audio/audio_service.dart';
import 'headunit_runtime_state.dart';
import 'services/service_registry.dart';
import 'services/remote_service_adapter.dart';
import 'application/application_manager.dart';
import 'errors/application_error_reporter_impl.dart';
import 'errors/flutter_framework_error_handler.dart';

class HeadunitRuntime {
  final AudioService _audioService;
  final ApplicationErrorReporterImpl _errorReporter =
      ApplicationErrorReporterImpl();
  late final FlutterFrameworkErrorHandler _flutterErrorHandler =
      FlutterFrameworkErrorHandler(errorReporter: _errorReporter);
  final ServiceRegistry _serviceRegistry = ServiceRegistry();
  late final ApplicationManager _applicationManager = ApplicationManager(
    serviceRegistry: _serviceRegistry,
    errorReporter: _errorReporter,
  );
  HeadunitRuntimeState _state = HeadunitRuntimeState.created;
  bool _disposeRequested = false;

  Future<void>? _initializationFuture;
  Future<void>? _disposalFuture;

  HeadunitRuntimeState get state => _state;

  bool get isRunning =>
      _state == HeadunitRuntimeState.running && !_disposeRequested;

  AudioService get audioService {
    if (!isRunning) {
      throw StateError(
        'AudioService is only available when the runtime is running.',
      );
    }
    return _audioService;
  }

  ApplicationErrorReporter get errorReporter => _errorReporter;

  ApplicationManager get applicationManager {
    if (!isRunning) {
      throw StateError(
        'ApplicationManager is only available while the runtime is running.',
      );
    }
    return _applicationManager;
  }

  HeadunitRuntime({AudioService? audioService})
      : _audioService = audioService ?? AudioService();

  Future<void> initialize() {
    if (_disposeRequested) {
      throw StateError('Runtime is shutting down or has been disposed.');
    }
    if (_state == HeadunitRuntimeState.running) {
      return Future<void>.value();
    }
    if (_initializationFuture != null) {
      return _initializationFuture!;
    }
    if (_state != HeadunitRuntimeState.created) {
      throw StateError('Cannot initialize runtime in state: $_state');
    }

    _state = HeadunitRuntimeState.initializing;
    final Future<void> initialization = _initializeInternal();
    _initializationFuture = initialization;
    return initialization;
  }

  Future<void> _initializeInternal() async {
    try {
      final bool audioInitialized = await _audioService.initialize();
      if (!audioInitialized) {
        throw StateError('Failed to initialize AudioService.');
      }
      _serviceRegistry.register<AudioService>(
        key: AudioService.serviceKey,
        instance: _audioService,
        requiredCapabilities: <CapabilityId>[
          CapabilityId('audio.sessions.manage'),
        ],
      );

      _flutterErrorHandler.install();
      _state = HeadunitRuntimeState.running;
    } catch (error, stackTrace) {
      _state = HeadunitRuntimeState.failed;
      _errorReporter.report(
        ApplicationError(
          applicationId: null,
          source: ApplicationErrorSource.startup,
          severity: ApplicationErrorSeverity.critical,
          message: 'Headunit runtime initialization failed.',
          error: error,
          stackTrace: stackTrace,
          timestamp: DateTime.now(),
        ),
      );
      rethrow;
    } finally {
      _initializationFuture = null;
    }
  }

  ServiceBroker createServiceBroker(ApplicationLaunchContext context) {
    _ensureRunning();
    return _serviceRegistry.createBroker(context);
  }

  /// Creates a capability-scoped broker suitable for a remote application.
  RemoteServiceBroker createRemoteServiceBroker(
    ApplicationLaunchContext context,
  ) {
    _ensureRunning();
    return _serviceRegistry.createBroker(context);
  }

  /// Registers a serializable RPC surface for an existing headunit service.
  ///
  /// The adapter is separate from the in-process service object so no Dart
  /// instances or platform handles cross the application process boundary.
  void registerRemoteService(RemoteServiceAdapter adapter) {
    _ensureRunning();
    _serviceRegistry.registerRemoteService(adapter);
  }

  bool unregisterService(ServiceId serviceId) {
    _ensureRunning();
    return _serviceRegistry.unregister(serviceId);
  }

  void _ensureRunning() {
    if (!isRunning) {
      throw StateError('HeadunitRuntime is not running.');
    }
  }

  Future<void> dispose() {
    if (_disposalFuture != null) {
      return _disposalFuture!;
    }
    if (_state == HeadunitRuntimeState.disposed) {
      return Future<void>.value();
    }

    _disposeRequested = true;
    final Future<void> operation = _disposeInternal();
    _disposalFuture = operation;
    return operation;
  }

  Future<void> _disposeInternal() async {
    final Future<void>? initialization = _initializationFuture;
    if (initialization != null) {
      try {
        await initialization;
      } catch (_) {
        // Clean up even if initialization failed.
      }
    }
    if (_state == HeadunitRuntimeState.disposed) {
      return;
    }

    _state = HeadunitRuntimeState.disposing;
    Object? firstError;
    StackTrace? firstStackTrace;

    try {
      await _applicationManager.dispose();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    try {
      await _audioService.dispose();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    _serviceRegistry.dispose();

    try {
      _flutterErrorHandler.dispose();
      await _errorReporter.dispose();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    if (firstError != null) {
      _state = HeadunitRuntimeState.failed;
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
    _state = HeadunitRuntimeState.disposed;
  }
}
