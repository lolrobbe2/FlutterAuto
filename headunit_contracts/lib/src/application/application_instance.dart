import 'dart:async';

import 'application_id.dart';
import 'application_lifecycle_event.dart';
import 'application_lifecycle_state.dart';

abstract interface class ApplicationInstance {
  ApplicationId get id;

  ApplicationLifecycleState get state;

  Stream<ApplicationLifecycleEvent> get lifecycleEvents;

  Future<void> start();

  Future<void> setForeground();

  Future<void> setBackground();

  Future<void> stop();
}