import 'dart:async';

import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:headunit_runtime/headunit_runtime.dart';

const String testApplicationId = 'com.example.test_app';

final CapabilityId audioCapability = CapabilityId('audio.sessions.manage');

ApplicationId createTestApplicationId([String value = testApplicationId]) {
  return ApplicationId(value);
}

ApplicationManifest createTestManifest({
  String id = testApplicationId,
  String name = 'Test Application',
  Iterable<CapabilityId>? requestedCapabilities,
}) {
  return ApplicationManifest(
    id: ApplicationId(id),
    name: name,
    version: '1.0.0',
    minimumFrameworkVersion: '0.1.0',
    runtime: ApplicationRuntimeKind.flutter,
    requestedCapabilities: requestedCapabilities ?? [audioCapability],
  );
}

ApplicationRegistration createTestRegistration({
  String id = testApplicationId,
  Iterable<CapabilityId>? requestedCapabilities,
  Iterable<CapabilityId>? grantedCapabilities,
  ApplicationBackgroundPolicy backgroundPolicy =
      ApplicationBackgroundPolicy.keepMounted,
}) {
  final List<CapabilityId> requested =
      requestedCapabilities?.toList() ?? [audioCapability];

  return ApplicationRegistration(
    manifest: createTestManifest(id: id, requestedCapabilities: requested),
    grantedCapabilities: grantedCapabilities ?? requested,
    backgroundPolicy: backgroundPolicy,
  );
}

ApplicationLaunchContext createTestLaunchContext({
  String id = testApplicationId,
  Iterable<CapabilityId> grantedCapabilities = const [],
}) {
  return ApplicationLaunchContext(
    applicationId: ApplicationId(id),
    grantedCapabilities: grantedCapabilities,
  );
}

class FakeAudioService extends AudioService {
  int initializeCalls = 0;
  int disposeCalls = 0;

  bool initializeResult = true;

  Completer<bool>? initializeCompleter;

  @override
  Future<bool> initialize() async {
    initializeCalls++;

    final Completer<bool>? completer = initializeCompleter;

    if (completer != null) {
      return completer.future;
    }

    return initializeResult;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class FakeApplicationRuntime implements ApplicationRuntime {
  @override
  final ApplicationRuntimeKind kind;

  final List<FakeApplicationInstance> instances = [];

  final List<ServiceBroker> receivedBrokers = [];

  int createInstanceCalls = 0;

  Completer<void>? createInstanceCompleter;

  Object? createError;
  Object? startError;
  Object? foregroundError;
  Object? backgroundError;
  Object? suspendError;
  Object? resumeError;

  FakeApplicationRuntime({this.kind = ApplicationRuntimeKind.flutter});

  @override
  Future<ApplicationInstance> createInstance({
    required ApplicationManifest manifest,
    required ApplicationLaunchContext context,
    required ServiceBroker serviceBroker,
  }) async {
    createInstanceCalls++;

    receivedBrokers.add(serviceBroker);

    final Completer<void>? completer = createInstanceCompleter;

    if (completer != null) {
      await completer.future;
    }

    final Object? error = createError;

    if (error != null) {
      throw error;
    }

    final FakeApplicationInstance instance = FakeApplicationInstance(
      id: manifest.id,
      startError: startError,
      foregroundError: foregroundError,
      backgroundError: backgroundError,
      suspendError: suspendError,
      resumeError: resumeError,
    );

    instances.add(instance);

    return instance;
  }
}

class FakeApplicationInstance implements ApplicationInstance {
  @override
  final ApplicationId id;

  final StreamController<ApplicationLifecycleEvent> _events =
      StreamController<ApplicationLifecycleEvent>.broadcast();

  final List<ApplicationLifecycleState> transitionHistory = [];
  int suspendCalls = 0;
  int resumeCalls = 0;
  ApplicationLifecycleState _state = ApplicationLifecycleState.stopped;

  Object? startError;
  Object? foregroundError;
  Object? backgroundError;
  Object? suspendError;
  Object? resumeError;

  int startCalls = 0;
  int foregroundCalls = 0;
  int backgroundCalls = 0;
  int stopCalls = 0;

  FakeApplicationInstance({
    required this.id,
    this.startError,
    this.foregroundError,
    this.backgroundError,
    this.suspendError,
    this.resumeError,
  });
  @override
  ApplicationLifecycleState get state => _state;

  @override
  Stream<ApplicationLifecycleEvent> get lifecycleEvents => _events.stream;

  @override
  Future<void> start() async {
    startCalls++;

    _transition(ApplicationLifecycleState.starting);

    final Object? error = startError;

    if (error != null) {
      _transition(ApplicationLifecycleState.failed);
      throw error;
    }

    _transition(ApplicationLifecycleState.background);
  }

  @override
  Future<void> setForeground() async {
    foregroundCalls++;

    if (foregroundError != null) {
      _transition(ApplicationLifecycleState.failed);
      throw foregroundError!;
    }

    _transition(ApplicationLifecycleState.foreground);
  }

  @override
  Future<void> setBackground() async {
    backgroundCalls++;

    if (backgroundError != null) {
      _transition(ApplicationLifecycleState.failed);
      throw backgroundError!;
    }

    _transition(ApplicationLifecycleState.background);
  }

  @override
  Future<void> suspend() async {
    suspendCalls++;

    if (suspendError != null) {
      _transition(ApplicationLifecycleState.failed);
      throw suspendError!;
    }

    _transition(ApplicationLifecycleState.suspended);
  }

  @override
  Future<void> resume() async {
    resumeCalls++;

    if (resumeError != null) {
      _transition(ApplicationLifecycleState.failed);
      throw resumeError!;
    }

    _transition(ApplicationLifecycleState.background);
  }

  @override
  Future<void> stop() async {
    stopCalls++;

    if (_state == ApplicationLifecycleState.stopped) {
      return;
    }

    if (_state == ApplicationLifecycleState.failed) {
      _transition(ApplicationLifecycleState.stopped);
      return;
    }

    _transition(ApplicationLifecycleState.stopping);
    _transition(ApplicationLifecycleState.stopped);
  }

  void _transition(ApplicationLifecycleState next) {
    if (!_state.canTransitionTo(next)) {
      throw StateError(
        'Invalid lifecycle transition: ${_state.name} -> ${next.name}',
      );
    }

    final ApplicationLifecycleState previous = _state;

    _state = next;
    transitionHistory.add(next);

    _events.add(
      ApplicationLifecycleEvent(
        applicationId: id,
        previousState: previous,
        currentState: next,
        timestamp: DateTime.now(),
      ),
    );
  }
}
