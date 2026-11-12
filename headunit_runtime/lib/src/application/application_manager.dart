import 'dart:async';

import 'package:headunit_contracts/headunit_contracts.dart';

import '../../headunit_runtime.dart';
import '../services/service_registry.dart';
import 'application_manager_event.dart';

class ApplicationManager {
  final ServiceRegistry _serviceRegistry;

  final Map<ApplicationId, ApplicationRegistration> _registrations = {};

  final Map<ApplicationId, ApplicationInstance> _instances = {};

  final Map<ApplicationRuntimeKind, ApplicationRuntime> _runtimes = {};

  final Map<ApplicationId, Future<ApplicationInstance>> _launchOperations = {};

  final StreamController<ApplicationManagerEvent> _events =
      StreamController<ApplicationManagerEvent>.broadcast();
  final ApplicationErrorReporter _errorReporter;

  ApplicationId? _foregroundApplicationId;
  bool _disposing = false;
  bool _disposed = false;
  int _transitionSequence = 0;
  Future<void>? _disposalFuture;
  Future<void> _transitionQueue = Future<void>.value();

  ApplicationManager({
    required ServiceRegistry serviceRegistry,
    required ApplicationErrorReporter errorReporter,
  }) : _serviceRegistry = serviceRegistry,
       _errorReporter = errorReporter;

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

  void _reportError({
    required ApplicationId applicationId,
    required ApplicationErrorSource source,
    required String message,
    required Object error,
    required StackTrace stackTrace,
    ApplicationErrorSeverity severity = ApplicationErrorSeverity.error,
  }) {
    _errorReporter.report(
      ApplicationError(
        applicationId: applicationId,
        source: source,
        severity: severity,
        message: message,
        error: error,
        stackTrace: stackTrace,
        timestamp: DateTime.now(),
      ),
    );
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
          } catch (error, stackTrace) {
            _reportError(
              applicationId: id,
              source: ApplicationErrorSource.lifecycle,
              message: 'Application $id failed to resume.',
              error: error,
              stackTrace: stackTrace,
            );

            await _cleanupFailedInstance(id, instance);
            rethrow;
          }

          try {
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

    late final ApplicationInstance newInstance;

    try {
      newInstance = await runtime.createInstance(
        manifest: manifest,
        context: context,
        serviceBroker: serviceBroker,
      );
    } catch (error, stackTrace) {
      _reportError(
        applicationId: id,
        source: ApplicationErrorSource.startup,
        message: 'Runtime failed to create application $id.',
        error: error,
        stackTrace: stackTrace,
      );

      rethrow;
    }

    if (newInstance.id != id) {
      final StateError error = StateError(
        'Runtime created an instance with ID ${newInstance.id}, '
        'but $id was requested.',
      );

      _reportError(
        applicationId: id,
        source: ApplicationErrorSource.startup,
        message: 'Runtime created an application with an unexpected ID.',
        error: error,
        stackTrace: StackTrace.current,
      );

      throw error;
    }

    _instances[id] = newInstance;

    _emitEvent(
      ApplicationManagerEventType.applicationsChanged,
      applicationId: id,
    );

    try {
      try {
        await newInstance.start();
      } catch (error, stackTrace) {
        _reportError(
          applicationId: id,
          source: ApplicationErrorSource.startup,
          message: 'Application $id failed to start.',
          error: error,
          stackTrace: stackTrace,
        );

        rethrow;
      }

      if (newInstance.state != ApplicationLifecycleState.background) {
        final StateError error = StateError(
          'Application $id must enter the background state after startup.',
        );

        _reportError(
          applicationId: id,
          source: ApplicationErrorSource.startup,
          message: 'Application $id entered an unexpected state after startup.',
          error: error,
          stackTrace: StackTrace.current,
        );

        throw error;
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
      } catch (error, stackTrace) {
        _reportError(
          applicationId: id,
          source: ApplicationErrorSource.lifecycle,
          severity: ApplicationErrorSeverity.warning,
          message: 'Failed to stop application $id during startup cleanup.',
          error: error,
          stackTrace: stackTrace,
        );
      }

      rethrow;
    }
  }

  Future<void> setForeground(ApplicationId id) {
    _ensureActive();
    return _enqueueTransition(() => _setForegroundInternal(id));
  }

  Future<void> setBackground(ApplicationId id) {
    _ensureActive();
    return _enqueueTransition(() => _setBackgroundInternal(id));
  }

  Future<void> _cleanupFailedInstance(
    ApplicationId id,
    ApplicationInstance instance,
  ) async {
    try {
      await instance.stop();
    } catch (error, stackTrace) {
      _reportError(
        applicationId: id,
        source: ApplicationErrorSource.lifecycle,
        severity: ApplicationErrorSeverity.warning,
        message: 'Failed to stop application $id during cleanup.',
        error: error,
        stackTrace: stackTrace,
      );
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
      } catch (error, stackTrace) {
        _reportError(
          applicationId: id,
          source: ApplicationErrorSource.lifecycle,
          message: 'Application $id failed to resume before foregrounding.',
          error: error,
          stackTrace: stackTrace,
        );

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
    } catch (error, stackTrace) {
      _reportError(
        applicationId: id,
        source: ApplicationErrorSource.lifecycle,
        message: 'Application $id failed to enter the foreground.',
        error: error,
        stackTrace: stackTrace,
      );

      if (target.state == ApplicationLifecycleState.failed) {
        await _cleanupFailedInstance(id, target);
      }

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
        } catch (restoreError, restoreStackTrace) {
          _reportError(
            applicationId: previousId!,
            source: ApplicationErrorSource.lifecycle,
            severity: ApplicationErrorSeverity.warning,
            message: 'Failed to restore the previous foreground application.',
            error: restoreError,
            stackTrace: restoreStackTrace,
          );

          await _cleanupFailedInstance(previousId, previous);
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
    } catch (error, stackTrace) {
      _reportError(
        applicationId: id,
        source: ApplicationErrorSource.lifecycle,
        message: 'Application $id failed to enter the background.',
        error: error,
        stackTrace: stackTrace,
      );

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
        } catch (error, stackTrace) {
          _reportError(
            applicationId: id,
            source: ApplicationErrorSource.lifecycle,
            message: 'Application $id failed to suspend.',
            error: error,
            stackTrace: stackTrace,
          );

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
    } catch (error, stackTrace) {
      _reportError(
        applicationId: id,
        source: ApplicationErrorSource.lifecycle,
        message: 'Application $id failed to stop.',
        error: error,
        stackTrace: stackTrace,
      );

      rethrow;
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

    for (int i = 0; i < pendingLaunches.length; i++) {
      try {
        await pendingLaunches[i];
      } catch (error) {}
    }

    if (_transitionSequence > 0) {
      await _transitionQueue;
    }

    Object? firstError;
    StackTrace? firstStackTrace;

    for (final ApplicationId id in _instances.keys.toList()) {
      final ApplicationInstance? instance = _instances[id];

      try {
        if (instance != null) {
          await instance.stop();
        }
      } catch (error, stackTrace) {
        _reportError(
          applicationId: id,
          source: ApplicationErrorSource.lifecycle,
          message: 'Application $id failed to stop during manager disposal.',
          error: error,
          stackTrace: stackTrace,
        );

        firstError ??= error;
        firstStackTrace ??= stackTrace;
      } finally {
        _instances.remove(id);
      }
    }

    await _events.close();
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
    final Future<void> transition = _transitionQueue.then<void>(
      (_) => operation(),
    );

    // Keep the queue usable even when an individual transition fails.
    // The returned transition still propagates its original error.
    _transitionQueue = transition.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );

    return transition;
  }
}
