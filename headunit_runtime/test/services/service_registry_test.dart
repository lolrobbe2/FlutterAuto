import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:headunit_runtime/src/services/service_registry.dart';

import '../support/test_fixtures.dart';

class TestService {
  final String value;

  TestService(this.value);
}

void main() {
  group('ServiceRegistry', () {
    late ServiceRegistry registry;
    late ServiceKey<TestService> serviceKey;
    late TestService service;

    setUp(() {
      registry = ServiceRegistry();

      serviceKey = ServiceKey<TestService>(
        ServiceId('headunit.test'),
      );

      service = TestService('test service');
    });

    tearDown(() {
      registry.dispose();
    });

    test('registers and resolves a service', () {
      registry.register<TestService>(
        key: serviceKey,
        instance: service,
      );

      final ServiceBroker broker =
          registry.createBroker(createTestLaunchContext());

      final TestService resolved =
          broker.getService(serviceKey);

      expect(identical(resolved, service), isTrue);
    });

    test('denies access when required capability is missing', () {
      registry.register<TestService>(
        key: serviceKey,
        instance: service,
        requiredCapabilities: [audioCapability],
      );

      final ServiceBroker broker =
          registry.createBroker(createTestLaunchContext());

      expect(
        () => broker.getService(serviceKey),
        throwsA(isA<ServiceAccessDeniedException>()),
      );
    });

    test('allows access when all capabilities are granted', () {
      registry.register<TestService>(
        key: serviceKey,
        instance: service,
        requiredCapabilities: [audioCapability],
      );

      final ServiceBroker broker = registry.createBroker(
        createTestLaunchContext(
          grantedCapabilities: [audioCapability],
        ),
      );

      expect(
        identical(broker.getService(serviceKey), service),
        isTrue,
      );
    });

    test('checks multiple required capabilities', () {
      final CapabilityId locationCapability =
          CapabilityId('navigation.location.read');

      registry.register<TestService>(
        key: serviceKey,
        instance: service,
        requiredCapabilities: [
          audioCapability,
          locationCapability,
        ],
      );

      final ServiceBroker broker = registry.createBroker(
        createTestLaunchContext(
          grantedCapabilities: [audioCapability],
        ),
      );

      expect(
        () => broker.getService(serviceKey),
        throwsA(
          isA<ServiceAccessDeniedException>().having(
            (ServiceAccessDeniedException error) =>
                error.missingCapabilities,
            'missingCapabilities',
            contains(locationCapability),
          ),
        ),
      );
    });

    test('throws when service does not exist', () {
      final ServiceBroker broker =
          registry.createBroker(createTestLaunchContext());

      final ServiceKey<TestService> unknownKey =
          ServiceKey<TestService>(
        ServiceId('headunit.unknown'),
      );

      expect(
        () => broker.getService(unknownKey),
        throwsA(isA<ServiceNotFoundException>()),
      );
    });

    test('rejects duplicate registrations', () {
      registry.register<TestService>(
        key: serviceKey,
        instance: service,
      );

      expect(
        () => registry.register<TestService>(
          key: serviceKey,
          instance: TestService('another service'),
        ),
        throwsStateError,
      );
    });

    test('detects a type mismatch', () {
      registry.register<TestService>(
        key: serviceKey,
        instance: service,
      );

      final ServiceKey<String> incorrectKey =
          ServiceKey<String>(serviceKey.id);

      final ServiceBroker broker =
          registry.createBroker(createTestLaunchContext());

      expect(
        () => broker.getService(incorrectKey),
        throwsA(isA<ServiceTypeMismatchException>()),
      );
    });

    test('unregisters a service', () {
      registry.register<TestService>(
        key: serviceKey,
        instance: service,
      );

      expect(registry.unregister(serviceKey.id), isTrue);
      expect(registry.unregister(serviceKey.id), isFalse);

      final ServiceBroker broker =
          registry.createBroker(createTestLaunchContext());

      expect(
        () => broker.getService(serviceKey),
        throwsA(isA<ServiceNotFoundException>()),
      );
    });

    test('rejects registration after disposal', () {
      registry.dispose();

      expect(
        () => registry.register<TestService>(
          key: serviceKey,
          instance: service,
        ),
        throwsStateError,
      );
    });

    test('rejects broker creation after disposal', () {
      registry.dispose();

      expect(
        () => registry.createBroker(createTestLaunchContext()),
        throwsStateError,
      );
    });

    test('rejects service resolution after disposal', () {
      registry.register<TestService>(
        key: serviceKey,
        instance: service,
      );

      final ServiceBroker broker =
          registry.createBroker(createTestLaunchContext());

      registry.dispose();

      expect(
        () => broker.getService(serviceKey),
        throwsStateError,
      );
    });

    test('does not expose its internal registry through the broker', () {
      registry.register<TestService>(
        key: serviceKey,
        instance: service,
      );

      final ServiceBroker broker =
          registry.createBroker(createTestLaunchContext());

      expect(broker, isA<ServiceBroker>());
      expect(broker.applicationId, createTestApplicationId());
    });
  });
}