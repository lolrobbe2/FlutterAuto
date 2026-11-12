import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:headunit_runtime/headunit_runtime.dart';
import 'package:headunit_runtime/src/services/service_registry.dart';

import '../support/test_fixtures.dart';

void main() {
  group('ApplicationManager', () {
    late ServiceRegistry serviceRegistry;
    late ApplicationManager manager;
    late FakeApplicationRuntime applicationRuntime;

    setUp(() {
      serviceRegistry = ServiceRegistry();

      manager = ApplicationManager(serviceRegistry: serviceRegistry);

      applicationRuntime = FakeApplicationRuntime();

      manager.registerRuntime(applicationRuntime);
    });

    tearDown(() async {
      await manager.dispose();
      serviceRegistry.dispose();
    });

    void registerApplication({
      String id = testApplicationId,
      ApplicationBackgroundPolicy backgroundPolicy =
          ApplicationBackgroundPolicy.keepMounted,
    }) {
      manager.registerApplication(
        createTestRegistration(id: id, backgroundPolicy: backgroundPolicy),
      );
    }

    test('registers an application', () {
      registerApplication();

      expect(manager.getRegistration(createTestApplicationId()), isNotNull);
    });

    test('rejects duplicate application registrations', () {
      registerApplication();

      expect(() => registerApplication(), throwsStateError);
    });

    test('does not grant capabilities that were not requested', () {
      expect(
        () => ApplicationRegistration(
          manifest: createTestManifest(
            requestedCapabilities: [audioCapability],
          ),
          grantedCapabilities: [CapabilityId('vehicle.speed.read')],
        ),
        throwsArgumentError,
      );
    });

    test('launches an application', () async {
      registerApplication();

      final ApplicationInstance instance = await manager.launch(
        createTestApplicationId(),
      );

      expect(instance.state, ApplicationLifecycleState.foreground);
      expect(instance.id, createTestApplicationId());

      expect(applicationRuntime.createInstanceCalls, 1);
      expect(applicationRuntime.instances, hasLength(1));
    });

    test('provides an application-scoped ServiceBroker', () async {
      registerApplication();

      await manager.launch(createTestApplicationId());

      expect(applicationRuntime.receivedBrokers, hasLength(1));

      expect(
        applicationRuntime.receivedBrokers.single.applicationId,
        createTestApplicationId(),
      );

      expect(
        applicationRuntime.receivedBrokers.single.hasCapability(
          audioCapability,
        ),
        isTrue,
      );
    });

    test('rejects launch when application is not registered', () async {
      await expectLater(
        manager.launch(createTestApplicationId()),
        throwsStateError,
      );
    });

    test('rejects launch when no matching runtime exists', () async {
      manager.registerApplication(
        ApplicationRegistration(
          manifest: ApplicationManifest(
            id: createTestApplicationId(),
            name: 'Web Application',
            version: '1.0.0',
            minimumFrameworkVersion: '0.1.0',
            runtime: ApplicationRuntimeKind.web,
            entryPoint: 'web/index.html',
          ),
          grantedCapabilities: [],
        ),
      );

      await expectLater(
        manager.launch(createTestApplicationId()),
        throwsStateError,
      );
    });

    test('returns an existing instance when launched again', () async {
      registerApplication();

      final ApplicationInstance first = await manager.launch(
        createTestApplicationId(),
      );

      final ApplicationInstance second = await manager.launch(
        createTestApplicationId(),
      );

      expect(identical(first, second), isTrue);
      expect(applicationRuntime.createInstanceCalls, 1);
    });

    test('shares a pending launch for concurrent requests', () async {
      registerApplication();

      applicationRuntime.createInstanceCompleter = Completer<void>();

      final Future<ApplicationInstance> first = manager.launch(
        createTestApplicationId(),
      );

      final Future<ApplicationInstance> second = manager.launch(
        createTestApplicationId(),
      );

      expect(applicationRuntime.createInstanceCalls, 1);

      applicationRuntime.createInstanceCompleter!.complete();

      final List<ApplicationInstance> results = await Future.wait([
        first,
        second,
      ]);

      expect(identical(results[0], results[1]), isTrue);
      expect(applicationRuntime.instances, hasLength(1));
    });

    test('returns a background application to foreground', () async {
      registerApplication();

      final ApplicationInstance instance = await manager.launch(
        createTestApplicationId(),
      );

      await manager.setBackground(instance.id);

      expect(instance.state, ApplicationLifecycleState.background);
      expect(manager.foregroundApplicationId, isNull);

      await manager.setForeground(instance.id);

      expect(instance.state, ApplicationLifecycleState.foreground);
      expect(manager.foregroundApplicationId, instance.id);
    });

    test('backgrounds the previous application when switching', () async {
      const String firstId = 'com.example.first';
      const String secondId = 'com.example.second';

      registerApplication(id: firstId);
      registerApplication(id: secondId);

      final ApplicationInstance first = await manager.launch(
        ApplicationId(firstId),
      );

      final ApplicationInstance second = await manager.launch(
        ApplicationId(secondId),
      );

      expect(first.state, ApplicationLifecycleState.background);
      expect(second.state, ApplicationLifecycleState.foreground);

      expect(manager.foregroundApplicationId, ApplicationId(secondId));
    });

    test('stops and removes an application', () async {
      registerApplication();

      final ApplicationInstance instance = await manager.launch(
        createTestApplicationId(),
      );

      await manager.stop(instance.id);

      expect(instance.state, ApplicationLifecycleState.stopped);
      expect(manager.getInstance(instance.id), isNull);
      expect(manager.foregroundApplicationId, isNull);
    });

    test('unregisters an application after it has stopped', () async {
      registerApplication();

      final ApplicationInstance instance = await manager.launch(
        createTestApplicationId(),
      );

      await manager.stop(instance.id);

      manager.unregisterApplication(instance.id);

      expect(manager.getRegistration(instance.id), isNull);
    });

    test('does not unregister a running application', () async {
      registerApplication();

      await manager.launch(createTestApplicationId());

      expect(
        () => manager.unregisterApplication(createTestApplicationId()),
        throwsStateError,
      );
    });

    test('stops all running applications', () async {
      const String firstId = 'com.example.first';
      const String secondId = 'com.example.second';

      registerApplication(id: firstId);
      registerApplication(id: secondId);

      final ApplicationInstance first = await manager.launch(
        ApplicationId(firstId),
      );

      final ApplicationInstance second = await manager.launch(
        ApplicationId(secondId),
      );

      await manager.stopAll();

      expect(first.state, ApplicationLifecycleState.stopped);
      expect(second.state, ApplicationLifecycleState.stopped);
      expect(manager.runningApplications, isEmpty);
      expect(manager.foregroundApplicationId, isNull);
    });

    test('cleans up an application when startup fails', () async {
      registerApplication();

      applicationRuntime.startError = StateError(
        'Simulated application startup failure.',
      );

      await expectLater(
        manager.launch(createTestApplicationId()),
        throwsStateError,
      );

      final FakeApplicationInstance instance =
          applicationRuntime.instances.single;

      expect(instance.state, ApplicationLifecycleState.stopped);
      expect(instance.stopCalls, 1);
      expect(manager.getInstance(instance.id), isNull);
      expect(manager.foregroundApplicationId, isNull);
    });

    test(
      'does not retain an application when runtime creation fails',
      () async {
        registerApplication();

        applicationRuntime.createError = StateError(
          'Simulated runtime creation failure.',
        );

        await expectLater(
          manager.launch(createTestApplicationId()),
          throwsStateError,
        );

        expect(manager.runningApplications, isEmpty);
      },
    );

    test('unregisters an unused runtime', () {
      manager.unregisterRuntime(ApplicationRuntimeKind.flutter);

      expect(
        () => manager.registerRuntime(applicationRuntime),
        returnsNormally,
      );
    });

    test('does not unregister a runtime with active applications', () async {
      registerApplication();

      await manager.launch(createTestApplicationId());

      expect(
        () => manager.unregisterRuntime(ApplicationRuntimeKind.flutter),
        throwsStateError,
      );
    });

    test('disposes all running applications', () async {
      registerApplication();

      final ApplicationInstance instance = await manager.launch(
        createTestApplicationId(),
      );

      await manager.dispose();

      expect(instance.state, ApplicationLifecycleState.stopped);
      expect(manager.runningApplications, isEmpty);
    });

    test('does not allow new operations after disposal', () async {
      await manager.dispose();

      expect(
        () => manager.registerRuntime(applicationRuntime),
        throwsStateError,
      );

      expect(
        () => manager.registerApplication(createTestRegistration()),
        throwsStateError,
      );
    });
    test('does not launch an application while shutting down', () async {
      registerApplication();

      applicationRuntime.createInstanceCompleter = Completer<void>();

      final Future<ApplicationInstance> launch = manager.launch(
        createTestApplicationId(),
      );

      final Future<void> disposal = manager.dispose();

      applicationRuntime.createInstanceCompleter!.complete();

      await expectLater(launch, throwsStateError);
      await disposal;

      final FakeApplicationInstance instance =
          applicationRuntime.instances.single;

      expect(instance.state, ApplicationLifecycleState.stopped);
      expect(manager.runningApplications, isEmpty);
    });
    test('keepMounted preserves the background application', () async {
      const String firstId = 'com.example.radio';
      const String secondId = 'com.example.navigation';

      registerApplication(id: firstId);
      registerApplication(id: secondId);

      final FakeApplicationInstance first = await manager.launch(
        ApplicationId(firstId),
      ) as FakeApplicationInstance;

      await manager.launch(ApplicationId(secondId));

      expect(first.state, ApplicationLifecycleState.background);
      expect(first.suspendCalls, 0);
      expect(manager.getInstance(ApplicationId(firstId)), same(first));
    });
    test(
      'suspend unmounts the application without destroying its instance',
      () async {
        const String firstId = 'com.example.radio';
        const String secondId = 'com.example.navigation';

        registerApplication(
          id: firstId,
          backgroundPolicy: ApplicationBackgroundPolicy.suspend,
        );

        registerApplication(id: secondId);

        final FakeApplicationInstance first = await manager.launch(
          ApplicationId(firstId),
        ) as FakeApplicationInstance;

        await manager.launch(ApplicationId(secondId));

        expect(first.state, ApplicationLifecycleState.suspended);
        expect(first.suspendCalls, 1);
        expect(manager.getInstance(ApplicationId(firstId)), same(first));

        await manager.launch(ApplicationId(firstId));

        expect(first.state, ApplicationLifecycleState.foreground);
        expect(first.resumeCalls, 1);

        // It is the same application instance, not a new one.
        expect(applicationRuntime.createInstanceCalls, 2);
      },
    );
    test('stop destroys the background application', () async {
      const String firstId = 'com.example.radio';
      const String secondId = 'com.example.navigation';

      registerApplication(
        id: firstId,
        backgroundPolicy: ApplicationBackgroundPolicy.stop,
      );

      registerApplication(id: secondId);

      final FakeApplicationInstance first = await manager.launch(
        ApplicationId(firstId),
      ) as FakeApplicationInstance;

      await manager.launch(ApplicationId(secondId));

      expect(first.state, ApplicationLifecycleState.stopped);
      expect(manager.getInstance(ApplicationId(firstId)), isNull);

      final ApplicationInstance relaunched = await manager.launch(
        ApplicationId(firstId),
      );

      expect(identical(first, relaunched), isFalse);
      expect(relaunched.state, ApplicationLifecycleState.foreground);
    });
    test('serializes rapid foreground changes', () async {
      const String firstId = 'com.example.first';
      const String secondId = 'com.example.second';
      const String thirdId = 'com.example.third';

      registerApplication(id: firstId);
      registerApplication(id: secondId);
      registerApplication(id: thirdId);

      await manager.launch(ApplicationId(firstId));
      await manager.launch(ApplicationId(secondId));
      await manager.launch(ApplicationId(thirdId));

      await Future.wait([
        manager.setForeground(ApplicationId(firstId)),
        manager.setForeground(ApplicationId(secondId)),
        manager.setForeground(ApplicationId(thirdId)),
      ]);

      expect(manager.foregroundApplicationId, ApplicationId(thirdId));

      final List<ApplicationInstance> instances = manager
          .runningApplications
          .values
          .toList();

      final int foregroundCount = instances
          .where(
            (ApplicationInstance instance) =>
                instance.state == ApplicationLifecycleState.foreground,
          )
          .length;

      expect(foregroundCount, 1);
    });
    test('cleans up application when background callback fails', () async {
      registerApplication();

      final FakeApplicationInstance instance = await manager.launch(
        createTestApplicationId(),
      ) as FakeApplicationInstance;

      instance.backgroundError = StateError('Background callback failed.');

      await expectLater(manager.setBackground(instance.id), throwsStateError);

      expect(instance.state, ApplicationLifecycleState.stopped);
      expect(manager.getInstance(instance.id), isNull);
      expect(manager.foregroundApplicationId, isNull);
    });
    test('cleans up application when suspension fails', () async {
      const String firstId = 'com.example.first';
      const String secondId = 'com.example.second';

      registerApplication(
        id: firstId,
        backgroundPolicy: ApplicationBackgroundPolicy.suspend,
      );

      registerApplication(id: secondId);

      final FakeApplicationInstance instance = await manager.launch(
        ApplicationId(firstId),
      ) as FakeApplicationInstance;

      instance.suspendError = StateError('Suspension failed.');

      await expectLater(
        manager.launch(ApplicationId(secondId)),
        throwsStateError,
      );

      expect(instance.state, ApplicationLifecycleState.stopped);
      expect(manager.getInstance(ApplicationId(firstId)), isNull);
    });
    test('cleans up an application when resumption fails', () async {
      const String firstId = 'com.example.first';
      const String secondId = 'com.example.second';

      registerApplication(
        id: firstId,
        backgroundPolicy: ApplicationBackgroundPolicy.suspend,
      );

      registerApplication(id: secondId);

      final FakeApplicationInstance instance = await manager.launch(
        ApplicationId(firstId),
      ) as FakeApplicationInstance;

      await manager.launch(ApplicationId(secondId));

      instance.resumeError = StateError('Resumption failed.');

      await expectLater(
        manager.launch(ApplicationId(firstId)),
        throwsStateError,
      );

      expect(instance.state, ApplicationLifecycleState.stopped);
      expect(manager.getInstance(ApplicationId(firstId)), isNull);
    });
  });
}
