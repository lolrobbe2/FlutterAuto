import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:headunit_runtime/headunit_runtime.dart';

import 'support/test_fixtures.dart';

void main() {
  group('HeadunitRuntime', () {
    late FakeAudioService audioService;
    late HeadunitRuntime runtime;

    setUp(() {
      audioService = FakeAudioService();

      runtime = HeadunitRuntime(audioService: audioService);
    });

    test('starts in the created state', () {
      expect(runtime.state, HeadunitRuntimeState.created);
    });

    test('initializes successfully', () async {
      await runtime.initialize();

      expect(runtime.state, HeadunitRuntimeState.running);
      expect(runtime.isRunning, isTrue);
      expect(audioService.initializeCalls, 1);
    });

    test('initializes audio only once', () async {
      await Future.wait([
        runtime.initialize(),
        runtime.initialize(),
        runtime.initialize(),
      ]);

      expect(audioService.initializeCalls, 1);
    });

    test('exposes audio only after initialization', () async {
      expect(() => runtime.audioService, throwsStateError);

      await runtime.initialize();

      expect(identical(runtime.audioService, audioService), isTrue);
    });

    test('exposes the application manager only after initialization', () async {
      expect(() => runtime.applicationManager, throwsStateError);

      await runtime.initialize();

      expect(runtime.applicationManager, isA<ApplicationManager>());
    });

    test('registers AudioService with the service registry', () async {
      await runtime.initialize();

      final ServiceBroker broker = runtime.createServiceBroker(
        createTestLaunchContext(grantedCapabilities: [audioCapability]),
      );

      final AudioService resolved = broker.getService(AudioService.serviceKey);

      expect(identical(resolved, audioService), isTrue);
    });

    test('rejects audio access without the required capability', () async {
      await runtime.initialize();

      final ServiceBroker broker = runtime.createServiceBroker(
        createTestLaunchContext(),
      );

      expect(
        () => broker.getService(AudioService.serviceKey),
        throwsA(isA<ServiceAccessDeniedException>()),
      );
    });

    test('does not allow broker creation before initialization', () {
      expect(
        () => runtime.createServiceBroker(createTestLaunchContext()),
        throwsStateError,
      );
    });

    test('enters failed state when audio initialization fails', () async {
      audioService.initializeResult = false;

      await expectLater(runtime.initialize(), throwsStateError);

      expect(runtime.state, HeadunitRuntimeState.failed);
      expect(runtime.isRunning, isFalse);
    });

    test('can be disposed after failed initialization', () async {
      audioService.initializeResult = false;

      await expectLater(runtime.initialize(), throwsStateError);

      await runtime.dispose();

      expect(runtime.state, HeadunitRuntimeState.disposed);
      expect(audioService.disposeCalls, 1);
    });

    test('shuts down audio during disposal', () async {
      await runtime.initialize();

      await runtime.dispose();

      expect(audioService.disposeCalls, 1);
      expect(runtime.state, HeadunitRuntimeState.disposed);
    });

    test('disposal is idempotent', () async {
      await runtime.initialize();

      await Future.wait([
        runtime.dispose(),
        runtime.dispose(),
        runtime.dispose(),
      ]);

      expect(audioService.disposeCalls, 1);
      expect(runtime.state, HeadunitRuntimeState.disposed);
    });

    test('waits for initialization before disposal', () async {
      final Completer<bool> initialization = Completer<bool>();

      audioService.initializeCompleter = initialization;

      final Future<void> initializationFuture = runtime.initialize();

      final Future<void> disposalFuture = runtime.dispose();

      initialization.complete(true);

      await Future.wait([initializationFuture, disposalFuture]);

      expect(audioService.initializeCalls, 1);
      expect(audioService.disposeCalls, 1);
      expect(runtime.state, HeadunitRuntimeState.disposed);
    });

    test('disposes applications before audio service', () async {
      await runtime.initialize();

      final ApplicationManager manager = runtime.applicationManager;

      final FakeApplicationRuntime applicationRuntime =
          FakeApplicationRuntime();

      manager.registerRuntime(applicationRuntime);
      manager.registerApplication(createTestRegistration());

      final ApplicationInstance instance = await manager.launch(
        createTestApplicationId(),
      );

      await runtime.dispose();

      expect(instance.state, ApplicationLifecycleState.stopped);
      expect(audioService.disposeCalls, 1);
    });

    test('can be disposed before initialization', () async {
      await runtime.dispose();

      expect(runtime.state, HeadunitRuntimeState.disposed);
      expect(audioService.disposeCalls, 1);
    });
    test('reports initialization failures', () async {
      audioService.initializeResult = false;

      await expectLater(runtime.initialize(), throwsStateError);

      expect(runtime.errorReporter.recentErrors, hasLength(1));

      final ApplicationError error = runtime.errorReporter.recentErrors.single;

      expect(error.applicationId, isNull);
      expect(error.source, ApplicationErrorSource.startup);
      expect(error.severity, ApplicationErrorSeverity.critical);
      expect(error.stackTrace, isNotNull);
    });
    test('disposes the error reporter during shutdown', () async {
      final ApplicationErrorReporter reporter = runtime.errorReporter;

      await runtime.dispose();

      expect(
        () => reporter.report(
          ApplicationError(
            applicationId: null,
            source: ApplicationErrorSource.runtime,
            severity: ApplicationErrorSeverity.error,
            message: 'Test error',
            error: Exception('Test error'),
            stackTrace: null,
            timestamp: DateTime.now(),
          ),
        ),
        throwsStateError,
      );
    });
  });
}
