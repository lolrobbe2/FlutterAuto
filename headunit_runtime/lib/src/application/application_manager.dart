import 'package:headunit_contracts/headunit_contracts.dart';

import '../services/service_registry.dart';
import 'application_registration.dart';

class ApplicationManager {
  final ServiceRegistry _serviceRegistry;

  final Map<ApplicationId, ApplicationRegistration> _registrations = {};

  final Map<ApplicationId, ApplicationInstance> _instances = {};

  final Map<ApplicationRuntimeKind, ApplicationRuntime> _runtimes = {};

  final Map<ApplicationId, Future<ApplicationInstance>> _launchOperations = {};

  ApplicationId? _foregroundApplicationId;

  bool _disposed = false;
  Future<void>? _disposalFuture;

  ApplicationManager({required ServiceRegistry serviceRegistry})
    : _serviceRegistry = serviceRegistry;

  ApplicationId? get foregroundApplicationId => _foregroundApplicationId;

  Map<ApplicationId, ApplicationInstance> get runningApplications =>
      Map<ApplicationId, ApplicationInstance>.unmodifiable(_instances);

  Map<ApplicationId, ApplicationRegistration> get registrations =>
      Map<ApplicationId, ApplicationRegistration>.unmodifiable(_registrations);

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
  }

  void unregisterApplication(ApplicationId id) {
    _ensureActive();

    if (_instances.containsKey(id)) {
      throw StateError(
        'Cannot unregister application $id while it is running.',
      );
    }

    _registrations.remove(id);
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
      if (instance.state == ApplicationLifecycleState.foreground) {
        return instance;
      }

      if (instance.state == ApplicationLifecycleState.background) {
        await setForeground(id);
        return instance;
      }

      if (instance.state == ApplicationLifecycleState.starting ||
          instance.state == ApplicationLifecycleState.stopping) {
        throw StateError(
          'Application $id is currently ${instance.state.name}.',
        );
      }

      _instances.remove(id);
      instance = null;
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

  Future<void> setForeground(ApplicationId id) async {
    _ensureActive();

    final ApplicationInstance? target = _instances[id];

    if (target == null) {
      throw StateError('Application $id is not running.');
    }

    if (target.state == ApplicationLifecycleState.foreground) {
      _foregroundApplicationId = id;
      return;
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
      await previous.setBackground();
      _foregroundApplicationId = null;
    }

    try {
      await target.setForeground();
      _foregroundApplicationId = id;
    } catch (_) {
      // Restore the previous foreground application if possible.
      if (previous != null &&
          previous.state == ApplicationLifecycleState.background) {
        try {
          await previous.setForeground();
          _foregroundApplicationId = previousId;
        } catch (_) {
          _foregroundApplicationId = null;
        }
      }

      rethrow;
    }
  }

  Future<void> setBackground(ApplicationId id) async {
    _ensureActive();

    final ApplicationInstance? instance = _instances[id];

    if (instance == null) {
      throw StateError('Application $id is not running.');
    }

    if (instance.state != ApplicationLifecycleState.foreground) {
      return;
    }

    await instance.setBackground();

    if (_foregroundApplicationId == id) {
      _foregroundApplicationId = null;
    }
  }

  Future<void> stop(ApplicationId id) async {
    _ensureActive();

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
      }
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

    _foregroundApplicationId = null;
    _disposed = true;

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('ApplicationManager has been disposed.');
    }
  }
}
