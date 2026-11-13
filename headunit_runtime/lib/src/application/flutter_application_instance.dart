import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

class FlutterApplicationInstance implements ApplicationInstance {
  @override
  final ApplicationId id;

  final HeadunitApplication _application;
  final HeadunitApplicationContext _context;

  final StreamController<ApplicationLifecycleEvent> _events =
      StreamController<ApplicationLifecycleEvent>.broadcast();

  ApplicationLifecycleState _state = ApplicationLifecycleState.stopped;

  Future<void>? _stopFuture;

  FlutterApplicationInstance({
    required this.id,
    required this._application,
    required this._context,
  });

  @override
  ApplicationLifecycleState get state => _state;

  @override
  Stream<ApplicationLifecycleEvent> get lifecycleEvents => _events.stream;

  /// The widget representing this application.
  ///
  /// The host should place this widget inside its application surface.
  Widget get widget => _application.build(_context);

  @override
  Future<void> start() async {
    if (_state != ApplicationLifecycleState.stopped) {
      throw StateError('Cannot start application $id from ${_state.name}.');
    }

    _transition(ApplicationLifecycleState.starting);

    try {
      await _application.onStart(_context);

      _transition(ApplicationLifecycleState.background);
    } catch (_) {
      _transition(ApplicationLifecycleState.failed);
      rethrow;
    }
  }

  @override
  Future<void> setForeground() async {
    _ensureState(ApplicationLifecycleState.background);

    try {
      await _application.onForeground(_context);

      _transition(ApplicationLifecycleState.foreground);
    } catch (_) {
      _transition(ApplicationLifecycleState.failed);
      rethrow;
    }
  }

  @override
  Future<void> setBackground() async {
    _ensureState(ApplicationLifecycleState.foreground);

    try {
      await _application.onBackground(_context);

      _transition(ApplicationLifecycleState.background);
    } catch (_) {
      _transition(ApplicationLifecycleState.failed);
      rethrow;
    }
  }

  @override
  Future<void> suspend() async {
    _ensureState(ApplicationLifecycleState.background);

    try {
      await _application.onSuspend(_context);

      _transition(ApplicationLifecycleState.suspended);
    } catch (_) {
      _transition(ApplicationLifecycleState.failed);
      rethrow;
    }
  }

  @override
  Future<void> resume() async {
    _ensureState(ApplicationLifecycleState.suspended);

    try {
      await _application.onResume(_context);

      _transition(ApplicationLifecycleState.background);
    } catch (_) {
      _transition(ApplicationLifecycleState.failed);
      rethrow;
    }
  }

  @override
  Future<void> stop() {
    if (_stopFuture != null) {
      return _stopFuture!;
    }

    if (_state == ApplicationLifecycleState.stopped) {
      return Future<void>.value();
    }

    final Future<void> operation = _stopInternal();

    _stopFuture = operation;

    return operation;
  }

  Future<void> _stopInternal() async {
    if (_state != ApplicationLifecycleState.failed) {
      _transition(ApplicationLifecycleState.stopping);
    }

    Object? firstError;
    StackTrace? firstStackTrace;

    try {
      await _application.onStop(_context);
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    } finally {
      _transition(ApplicationLifecycleState.stopped);
      await _events.close();
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  void _transition(ApplicationLifecycleState next) {
    if (!_state.canTransitionTo(next)) {
      throw StateError(
        'Invalid lifecycle transition for $id: '
        '${_state.name} -> ${next.name}.',
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

  void _ensureState(ApplicationLifecycleState expected) {
    if (_state != expected) {
      throw StateError(
        'Application $id is ${_state.name}; expected ${expected.name}.',
      );
    }
  }
}
