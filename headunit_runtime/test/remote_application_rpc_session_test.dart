import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_runtime/src/application/remote_application_rpc_session.dart';
import 'package:headunit_runtime/src/services/remote_service_adapter.dart';
import 'package:headunit_runtime/src/services/service_registry.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

void main() {
  group('RemoteApplicationRpcSession', () {
    late ServiceRegistry registry;
    late RemoteApplicationRpcSession session;
    late HeadunitConnection connection;

    final ApplicationId applicationId = ApplicationId('com.example.radio');
    final ServiceId serviceId = ServiceId('headunit.example');
    final CapabilityId capability = CapabilityId('example.echo');

    setUp(() async {
      registry = ServiceRegistry();
      registry.registerRemoteService(
        RemoteServiceAdapter(
          serviceId: serviceId,
          requiredCapabilities: <CapabilityId>[capability],
          methods: <String, RemoteServiceMethodHandler>{
            'echo': (Map<String, Object?> arguments) {
              return <String, Object?>{'value': arguments['value']};
            },
          },
        ),
      );

      final ApplicationLaunchContext context = ApplicationLaunchContext(
        applicationId: applicationId,
        grantedCapabilities: <CapabilityId>[capability],
        locale: 'en-US',
        productId: 'test-product',
      );
      final RemoteServiceBroker broker = registry.createBroker(context);
      session = await RemoteApplicationRpcSession.bind(
        context: context,
        serviceBroker: broker,
      );
      final RemoteApplicationEndpoint endpoint = session.endpoint;
      connection = await HeadunitConnection.connect(
        host: endpoint.host,
        port: endpoint.port,
        token: endpoint.token,
      );
    });

    tearDown(() async {
      await connection.close();
      await session.dispose();
      registry.dispose();
    });

    test(
      'authenticates and acquires a capability-authorized service',
      () async {
        expect(connection.applicationId, applicationId);
        expect(connection.locale, 'en-US');
        expect(connection.productId, 'test-product');
        expect(connection.hasCapability(capability), isTrue);

        final _EchoService service = await connection.services.acquire(
          _EchoService.key,
        );
        final Object? response = await service.echo('hello');
        expect(response, <String, Object?>{'value': 'hello'});
      },
    );

    test('rejects a broker with a broader capability grant', () async {
      final ApplicationLaunchContext restrictedContext =
          ApplicationLaunchContext(applicationId: applicationId);
      final ApplicationLaunchContext broaderContext = ApplicationLaunchContext(
        applicationId: applicationId,
        grantedCapabilities: <CapabilityId>[capability],
      );
      final RemoteServiceBroker broaderBroker = registry.createBroker(
        broaderContext,
      );

      await expectLater(
        RemoteApplicationRpcSession.bind(
          context: restrictedContext,
          serviceBroker: broaderBroker,
        ),
        throwsArgumentError,
      );
    });

    test('host rejects a service without a granted capability', () async {
      await connection.close();
      await session.dispose();

      final ApplicationLaunchContext deniedContext = ApplicationLaunchContext(
        applicationId: applicationId,
      );
      final RemoteServiceBroker deniedBroker = registry.createBroker(
        deniedContext,
      );
      session = await RemoteApplicationRpcSession.bind(
        context: deniedContext,
        serviceBroker: deniedBroker,
      );
      final RemoteApplicationEndpoint endpoint = session.endpoint;
      connection = await HeadunitConnection.connect(
        host: endpoint.host,
        port: endpoint.port,
        token: endpoint.token,
      );

      await expectLater(
        connection.services.acquireHandle(serviceId),
        throwsA(isA<RpcException>()),
      );
    });

    test('forwards lifecycle notifications to the app', () async {
      final Future<HeadunitHostEvent> notification =
          connection.notifications.first;

      session.sendLifecycleState(ApplicationLifecycleState.background);

      final HeadunitHostEvent received = await notification;
      expect(received.method, 'application.lifecycle');
      expect(received.parameters['state'], 'background');
    });

    test('forwards normalized pointer events to the app', () async {
      final Future<ApplicationPointerEvent> pointer =
          connection.pointerEvents.first;

      session.sendPointerEvent(
        ApplicationPointerEvent(
          pointerId: 2,
          phase: ApplicationPointerPhase.down,
          x: 0.25,
          y: 0.75,
          pressure: 0.8,
        ),
      );

      final ApplicationPointerEvent received = await pointer;
      expect(received.pointerId, 2);
      expect(received.phase, ApplicationPointerPhase.down);
      expect(received.x, 0.25);
      expect(received.y, 0.75);
      expect(received.pressure, 0.8);
    });

    test('forwards authorized service events to the app', () async {
      final RemoteServiceHandle handle = await connection.services
          .acquireHandle(serviceId);
      await handle.subscribeEvents();
      final Future<RemoteServiceEvent> event = connection.serviceEvents.first;

      session.publishServiceEvent(
        serviceId: serviceId,
        event: 'value.changed',
        data: <String, Object?>{'value': 12},
      );

      final RemoteServiceEvent received = await event;
      expect(received.serviceId, serviceId);
      expect(received.event, 'value.changed');
      expect(received.data['value'], 12);
    });
  });
}

class _EchoService {
  static final RemoteServiceKey<_EchoService> key =
      RemoteServiceKey<_EchoService>(
        serviceId: ServiceId('headunit.example'),
        create: _EchoService._,
      );

  final RemoteServiceHandle _remote;

  _EchoService._(this._remote);

  Future<Object?> echo(String value) {
    return _remote.invoke('echo', arguments: <String, Object?>{'value': value});
  }
}
