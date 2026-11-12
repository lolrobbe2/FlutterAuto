import 'dart:async';

import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:headunit_runtime/headunit_runtime.dart';

class ExampleApplicationRuntime implements ApplicationRuntime {
  @override
  ApplicationRuntimeKind get kind => ApplicationRuntimeKind.flutter;

  @override
  Future<ApplicationInstance> createInstance({
    required ApplicationManifest manifest,
    required ApplicationLaunchContext context,
    required ServiceBroker serviceBroker,
  }) async {
    return ExampleApplicationInstance(
      id: manifest.id,
      serviceBroker: serviceBroker,
    );
  }
}

class ExampleApplicationInstance implements ApplicationInstance {
  @override
  final ApplicationId id;

  final ServiceBroker _serviceBroker;

  final StreamController<ApplicationLifecycleEvent> _events =
      StreamController<ApplicationLifecycleEvent>.broadcast();

  ApplicationLifecycleState _state =
      ApplicationLifecycleState.stopped;

  ExampleApplicationInstance({
    required this.id,
    required this._serviceBroker,
  });

  @override
  ApplicationLifecycleState get state => _state;

  @override
  Stream<ApplicationLifecycleEvent> get lifecycleEvents =>
      _events.stream;

  @override
  Future<void> start() async {
    _transition(ApplicationLifecycleState.starting);

    // Verify that the application receives its own broker.
    _serviceBroker.getService(AudioService.serviceKey);

    _transition(ApplicationLifecycleState.background);
  }

  @override
  Future<void> setForeground() async {
    _transition(ApplicationLifecycleState.foreground);
  }

  @override
  Future<void> setBackground() async {
    _transition(ApplicationLifecycleState.background);
  }

  @override
  Future<void> stop() async {
    if (_state == ApplicationLifecycleState.stopped) {
      return;
    }

    _transition(ApplicationLifecycleState.stopping);
    _transition(ApplicationLifecycleState.stopped);

    await _events.close();
  }

  void _transition(ApplicationLifecycleState next) {
    if (!_state.canTransitionTo(next)) {
      throw StateError(
        'Invalid transition: ${_state.name} -> ${next.name}',
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
      ),
    );
  }

  @override
  Future<void> resume() {
    // TODO: implement resume
    throw UnimplementedError();
  }

  @override
  Future<void> suspend() {
    // TODO: implement suspend
    throw UnimplementedError();
  }
}