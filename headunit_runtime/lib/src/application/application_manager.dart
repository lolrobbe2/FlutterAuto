import 'dart:async';

import 'package:headunit_contracts/headunit_contracts.dart';

import '../../headunit_runtime.dart';
import '../services/service_registry.dart';
import 'application_registration.dart';
import 'application_manager_event.dart';

class ApplicationManager {
  final ServiceRegistry _serviceRegistry;

  final Map<ApplicationId, ApplicationRegistration> _registrations = {};

  final Map<ApplicationId, ApplicationInstance> _instances = {};

  final Map<ApplicationRuntimeKind, ApplicationRuntime> _runtimes = {};

  final Map<ApplicationId, Future<ApplicationInstance>> _launchOperations = {};

  final StreamController<ApplicationManagerEvent> _events =
      StreamController<ApplicationManagerEvent>.broadcast();

  ApplicationId? _foregroundApplicationId;
  bool _disposing = false;
  bool _disposed = false;
  Future<void>? _disposalFuture;
  Future<void> _transitionQueue = Future<void>.value();

  ApplicationManager({required ServiceRegistry serviceRegistry})
    : _serviceRegistry = serviceRegistry;

  ApplicationId? get foregroundApplicationId => _foregroundApplicationId;

  Map<ApplicationId, ApplicationInstance> get runningApplications =>
      Map<ApplicationId, ApplicationInstance>.unmodifiable(_instances);

  Map<ApplicationId, ApplicationRegistration> get registrations =>
      Map<ApplicationId, ApplicationRegistration>.unmodifiable(_registrations);

  Stream<ApplicationManagerEvent> get events => _events.stream;
  void registerRuntime(ApplicationRuntime runtime) {
    _ensureActive();

    if (_runtimes.containsKey(runtime.kind)) {
      throw StateError(
        'An application runtime for ${runtime.kind.name} '
        'is already registered.',
      );
    }

    _runtimes[runtime.kind] = runtime;
  }

  void unregisterRuntime(ApplicationRuntimeKind kind) {
    _ensureActive();

    final bool hasRunningApplications = _instances.values.any(
      (ApplicationInstance instance) =>
          _registrations[instance.id]?.manifest.runtime == kind,
    );

    if (hasRunningApplications) {
      throw StateError(
        'Cannot unregister ${kind.name} while applications '
        'using it are running.',
      );
    }

    _runtimes.remove(kind);
  }

  void registerApplication(ApplicationRegistration registration) {
    _ensureActive();

    final ApplicationId id = registration.manifest.id;

    if (_registrations.containsKey(id)) {
      throw StateError('Application $id is already registered.');
    }

    _registrations[id] = registration;

    _emitEvent(
      ApplicationManagerEventType.applicationsChanged,
      applicationId: id,
    );
  }

  void unregisterApplication(ApplicationId id) {
    _ensureActive();

    if (_instances.containsKey(id)) {
      throw StateError(
        'Cannot unregister application $id while it is running.',
      );
    }

    final ApplicationRegistration? removed = _registrations.remove(id);

    if (removed != null) {
      _emitEvent(
        ApplicationManagerEventType.applicationsChanged,
        applicationId: id,
      );
    }
  }

  ApplicationRegistration? getRegistration(ApplicationId id) {
    return _registrations[id];
  }

  ApplicationInstance? getInstance(ApplicationId id) {
    return _instances[id];
  }

  Future<ApplicationInstance> launch(ApplicationId id) {
    _ensureActive();

    final Future<ApplicationInstance>? existingOperation =
        _launchOperations[id];

    if (existingOperation != null) {
      return existingOperation;
    }

    final Future<ApplicationInstance> operation = _launchInternal(id);

    _launchOperations[id] = operation;

    return operation.whenComplete(() {
      if (identical(_launchOperations[id], operation)) {
        _launchOperations.remove(id);
      }
    });
  }

  Future<ApplicationInstance> _launchInternal(ApplicationId id) async {
    ApplicationInstance? instance = _instances[id];

    if (instance != null) {
      switch (instance.state) {
        case ApplicationLifecycleState.foreground:
          return instance;

        case ApplicationLifecycleState.background:
          await setForeground(id);
          return instance;

        case ApplicationLifecycleState.suspended:
          try {
            await instance.resume();
            await setForeground(id);

            return instance;
          } catch (_) {
            await _cleanupFailedInstance(id, instance);
            rethrow;
          }

        case ApplicationLifecycleState.starting:
        case ApplicationLifecycleState.stopping:
          throw StateError(
            'Application $id is currently ${instance.state.name}.',
          );

        case ApplicationLifecycleState.failed:
        case ApplicationLifecycleState.stopped:
          await _cleanupFailedInstance(id, instance);
          instance = null;
      }
    }
    final ApplicationRegistration? registration = _registrations[id];

    if (registration == null) {
      throw StateError('Application $id is not registered.');
    }

    final ApplicationManifest manifest = registration.manifest;

    final ApplicationRuntime? runtime = _runtimes[manifest.runtime];

    if (runtime == null) {
      throw StateError('No runtime registered for ${manifest.runtime.name}.');
    }

    final ApplicationLaunchContext context = ApplicationLaunchContext(
      applicationId: id,
      grantedCapabilities: registration.grantedCapabilities,
    );

    final ServiceBroker serviceBroker = _serviceRegistry.createBroker(context);

    final ApplicationInstance newInstance = await runtime.createInstance(
      manifest: manifest,
      context: context,
      serviceBroker: serviceBroker,
    );

    if (newInstance.id != id) {
      throw StateError(
        'Runtime created an instance with ID ${newInstance.id}, '
        'but $id was requested.',
      );
    }

    _instances[id] = newInstance;

    _emitEvent(
      ApplicationManagerEventType.applicationsChanged,
      applicationId: id,
    );

    try {
      await newInstance.start();
      if (newInstance.state != ApplicationLifecycleState.background) {
        throw StateError(
          'Application $id must enter the background state after startup.',
        );
      }

      await setForeground(id);

      return newInstance;
    } catch (_) {
      _instances.remove(id);

      if (_foregroundApplicationId == id) {
        _foregroundApplicationId = null;
      }

      try {
        await newInstance.stop();
      } catch (_) {
        // Preserve the original startup error.
      }

      rethrow;
    }
  }

  Future<void> setForeground(ApplicationId id) {
    return _enqueueTransition(() => _setForegroundInternal(id));
  }

  Future<void> setBackground(ApplicationId id) {
    return _enqueueTransition(() => _setBackgroundInternal(id));
  }

  Future<void> _cleanupFailedInstance(
    ApplicationId id,
    ApplicationInstance instance,
  ) async {
    try {
      await instance.stop();
    } catch (_) {
      // Continue removing the failed application.
    }

    if (identical(_instances[id], instance)) {
      _instances.remove(id);
    }

    if (_foregroundApplicationId == id) {
      _foregroundApplicationId = null;

      _emitEvent(
        ApplicationManagerEventType.foregroundChanged,
        applicationId: id,
        previousForegroundApplicationId: id,
      );
    }

    _emitEvent(
      ApplicationManagerEventType.applicationsChanged,
      applicationId: id,
    );
  }

  Future<void> _setForegroundInternal(ApplicationId id) async {
    _ensureActive();

    final ApplicationInstance? target = _instances[id];

    if (target == null) {
      throw StateError('Application $id is not running.');
    }

    if (target.state == ApplicationLifecycleState.foreground) {
      _foregroundApplicationId = id;
      return;
    }

    // Restore a suspended application before switching to it.
    if (target.state == ApplicationLifecycleState.suspended) {
      try {
        await target.resume();
      } catch (_) {
        await _cleanupFailedInstance(id, target);
        rethrow;
      }
    }

    if (target.state != ApplicationLifecycleState.background) {
      throw StateError(
        'Cannot foreground application $id from state ${target.state}.',
      );
    }

    final ApplicationId? previousId = _foregroundApplicationId;

    final ApplicationInstance? previous = previousId == null
        ? null
        : _instances[previousId];

    if (previous != null && previousId != id) {
      await _setBackgroundInternal(previousId!);
    }

    try {
      await target.setForeground();

      _foregroundApplicationId = id;

      _emitEvent(
        ApplicationManagerEventType.foregroundChanged,
        applicationId: id,
        previousForegroundApplicationId: previousId,
      );
    } catch (_) {
      if (target.state == ApplicationLifecycleState.failed) {
        await _cleanupFailedInstance(id, target);
      }

      // Try to restore the previous application if it is still registered
      // as a running instance.
      if (previous != null &&
          identical(_instances[previousId], previous) &&
          previous.state != ApplicationLifecycleState.failed) {
        try {
          if (previous.state == ApplicationLifecycleState.suspended) {
            await previous.resume();
          }

          if (previous.state == ApplicationLifecycleState.background) {
            await previous.setForeground();

            _foregroundApplicationId = previousId;

            _emitEvent(
              ApplicationManagerEventType.foregroundChanged,
              applicationId: previousId,
              previousForegroundApplicationId: id,
            );
          }
        } catch (_) {
          await _cleanupFailedInstance(previousId!, previous);
        }
      }

      rethrow;
    }
  }

  Future<void> _setBackgroundInternal(ApplicationId id) async {
    _ensureActive();

    final ApplicationInstance? instance = _instances[id];

    if (instance == null) {
      throw StateError('Application $id is not running.');
    }

    if (instance.state != ApplicationLifecycleState.foreground) {
      return;
    }

    try {
      await instance.setBackground();
    } catch (_) {
      if (instance.state == ApplicationLifecycleState.failed) {
        await _cleanupFailedInstance(id, instance);
      }

      rethrow;
    }

    if (_foregroundApplicationId == id) {
      _foregroundApplicationId = null;

      _emitEvent(
        ApplicationManagerEventType.foregroundChanged,
        applicationId: id,
        previousForegroundApplicationId: id,
      );
    }

    final ApplicationRegistration registration = _registrations[id]!;

    switch (registration.backgroundPolicy) {
      case ApplicationBackgroundPolicy.keepMounted:
        break;

      case ApplicationBackgroundPolicy.suspend:
        try {
          await instance.suspend();

          _emitEvent(
            ApplicationManagerEventType.applicationsChanged,
            applicationId: id,
          );
        } catch (_) {
          await _cleanupFailedInstance(id, instance);
          rethrow;
        }

      case ApplicationBackgroundPolicy.stop:
        await _stopInternal(id);
    }
  }

  Future<void> stop(ApplicationId id) {
    return _enqueueTransition(() => _stopInternal(id));
  }

  Future<void> _stopInternal(ApplicationId id) async {
    final ApplicationInstance? instance = _instances[id];

    if (instance == null) {
      return;
    }

    try {
      await instance.stop();
    } finally {
      _instances.remove(id);

      if (_foregroundApplicationId == id) {
        _foregroundApplicationId = null;

        _emitEvent(
          ApplicationManagerEventType.foregroundChanged,
          applicationId: id,
          previousForegroundApplicationId: id,
        );
      }

      _emitEvent(
        ApplicationManagerEventType.applicationsChanged,
        applicationId: id,
      );
    }
  }

  Future<void> stopAll() async {
    _ensureActive();

    final List<ApplicationId> ids = _instances.keys.toList();

    for (final ApplicationId id in ids) {
      await stop(id);
    }
  }

  Future<void> dispose() {
    if (_disposalFuture != null) {
      return _disposalFuture!;
    }

    if (_disposed) {
      return Future<void>.value();
    }

    _disposing = true;

    final Future<void> operation = _disposeInternal();

    _disposalFuture = operation;

    return operation;
  }

  Future<void> _disposeInternal() async {
    final List<Future<ApplicationInstance>> pendingLaunches = _launchOperations
        .values
        .toList();

    for (final Future<ApplicationInstance> launch in pendingLaunches) {
      try {
        await launch;
      } catch (_) {
        // A failed launch must not prevent shutdown.
      }
    }

    await _transitionQueue;

    Object? firstError;
    StackTrace? firstStackTrace;

    for (final ApplicationId id in _instances.keys.toList()) {
      try {
        final ApplicationInstance? instance = _instances[id];

        if (instance != null) {
          await instance.stop();
        }
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      } finally {
        _instances.remove(id);
      }
    }
    await _events.close();
    _foregroundApplicationId = null;
    _disposed = true;

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  void _ensureActive() {
    if (_disposed || _disposing) {
      throw StateError('ApplicationManager is disposing or disposed.');
    }
  }

  void _emitEvent(
    ApplicationManagerEventType type, {
    ApplicationId? applicationId,
    ApplicationId? previousForegroundApplicationId,
  }) {
    if (_events.isClosed) {
      return;
    }

    _events.add(
      ApplicationManagerEvent(
        type: type,
        applicationId: applicationId,
        previousForegroundApplicationId: previousForegroundApplicationId,
        foregroundApplicationId: _foregroundApplicationId,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> _enqueueTransition(Future<void> Function() operation) {
    final Future<void> previous = _transitionQueue;

    final Completer<void> release = Completer<void>();

    _transitionQueue = release.future;

    return _executeTransition(previous, release, operation);
  }

  Future<void> _executeTransition(
    Future<void> previous,
    Completer<void> release,
    Future<void> Function() operation,
  ) async {
    await previous;

    try {
      await operation();
    } finally {
      release.complete();
    }
  }
}
