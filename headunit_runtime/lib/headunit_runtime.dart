import 'package:headunit_contracts/headunit_contracts.dart';

import 'audio/audio_service.dart';
import 'headunit_runtime_state.dart';
import 'services/service_registry.dart';

class HeadunitRuntime {
  final AudioService _audioService = AudioService();
  final ServiceRegistry _serviceRegistry = ServiceRegistry();

  HeadunitRuntimeState _state = HeadunitRuntimeState.created;

  Future<void>? _initializationFuture;
  Future<void>? _disposalFuture;

  HeadunitRuntimeState get state => _state;

  bool get isRunning => _state == HeadunitRuntimeState.running;

  AudioService get audioService {
    if (!isRunning) {
      throw StateError(
        'AudioService is only available when the runtime is running.',
      );
    }

    return _audioService;
  }

  Future<void> initialize() {
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
        requiredCapabilities: [CapabilityId('audio.sessions.manage')],
      );

      _state = HeadunitRuntimeState.running;
    } catch (_) {
      _state = HeadunitRuntimeState.failed;
      rethrow;
    } finally {
      _initializationFuture = null;
    }
  }

  Future<void> dispose() {
    if (_state == HeadunitRuntimeState.disposed) {
      return Future<void>.value();
    }

    if (_disposalFuture != null) {
      return _disposalFuture!;
    }

    final Future<void> disposal = _disposeInternal();

    _disposalFuture = disposal;

    return disposal;
  }

  Future<void> _disposeInternal() async {
    final Future<void>? initialization = _initializationFuture;

    if (initialization != null) {
      try {
        await initialization;
      } catch (_) {
        // Initialization failed. Still clean up any partially
        // initialized framework services.
      }
    }

    if (_state == HeadunitRuntimeState.disposed) {
      return;
    }

    _state = HeadunitRuntimeState.disposing;

    try {
      //AUDIO SERVICE DISPOSAL
      try {
        await _audioService.dispose();
      } finally {
        _serviceRegistry.dispose();
      }

      _state = HeadunitRuntimeState.disposed;
    } catch (_) {
      _state = HeadunitRuntimeState.failed;
      rethrow;
    } finally {
      _disposalFuture = null;
    }
  }
}
