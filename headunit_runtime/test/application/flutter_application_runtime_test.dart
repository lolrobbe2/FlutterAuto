import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:headunit_runtime/headunit_runtime.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

class TestServiceBroker implements ServiceBroker {
  @override
  final ApplicationId applicationId;

  final Set<CapabilityId> capabilities;

  TestServiceBroker({
    required this.applicationId,
    Iterable<CapabilityId> capabilities = const [],
  }) : capabilities = capabilities.toSet();

  @override
  bool hasCapability(CapabilityId capability) {
    return capabilities.contains(capability);
  }

  @override
  T getService<T extends Object>(ServiceKey<T> key) {
    throw UnimplementedError();
  }
}

class RecordingApplication extends HeadunitApplication {
  final List<String> lifecycleCalls = [];

  @override
  Widget build(HeadunitApplicationContext context) {
    return Text('Hello from ${context.applicationId}');
  }

  @override
  Future<void> onStart(HeadunitApplicationContext context) async {
    lifecycleCalls.add('start');
  }

  @override
  Future<void> onForeground(HeadunitApplicationContext context) async {
    lifecycleCalls.add('foreground');
  }

  @override
  Future<void> onBackground(HeadunitApplicationContext context) async {
    lifecycleCalls.add('background');
  }

  @override
  Future<void> onStop(HeadunitApplicationContext context) async {
    lifecycleCalls.add('stop');
  }
}

void main() {
  group('FlutterApplicationRuntime', () {
    late FlutterApplicationRuntime runtime;
    late ApplicationId applicationId;
    late ApplicationManifest manifest;
    late ApplicationLaunchContext launchContext;
    late TestServiceBroker broker;

    late RecordingApplication application;

    setUp(() {
      runtime = FlutterApplicationRuntime();

      applicationId = ApplicationId('com.example.test_app');

      manifest = ApplicationManifest(
        id: applicationId,
        name: 'Test Application',
        version: '1.0.0',
        minimumFrameworkVersion: '0.1.0',
        runtime: ApplicationRuntimeKind.flutter,
      );

      launchContext = ApplicationLaunchContext(
        applicationId: applicationId,
        grantedCapabilities: [CapabilityId('audio.sessions.manage')],
        locale: 'en',
        productId: 'test_product',
      );

      broker = TestServiceBroker(
        applicationId: applicationId,
        capabilities: launchContext.grantedCapabilities,
      );

      runtime.registerApplication(
        id: applicationId,
        factory: () {
          application = RecordingApplication();
          return application;
        },
      );
    });

    tearDown(() {
      runtime.dispose();
    });

    test('identifies itself as Flutter runtime', () {
      expect(runtime.kind, ApplicationRuntimeKind.flutter);
    });

    test('registers an application factory', () {
      expect(runtime.isRegistered(applicationId), isTrue);
    });

    test('rejects duplicate application factories', () {
      expect(
        () => runtime.registerApplication(
          id: applicationId,
          factory: RecordingApplication.new,
        ),
        throwsStateError,
      );
    });

    test('creates a Flutter application instance', () async {
      final ApplicationInstance instance = await runtime.createInstance(
        manifest: manifest,
        context: launchContext,
        serviceBroker: broker,
      );

      expect(instance, isA<FlutterApplicationInstance>());
      expect(instance.id, applicationId);
      expect(instance.state, ApplicationLifecycleState.stopped);
    });

    test('creates a fresh application object for each instance', () async {
      final ApplicationInstance first = await runtime.createInstance(
        manifest: manifest,
        context: launchContext,
        serviceBroker: broker,
      );

      final RecordingApplication firstApplication = application;

      final ApplicationInstance second = await runtime.createInstance(
        manifest: manifest,
        context: launchContext,
        serviceBroker: broker,
      );

      final RecordingApplication secondApplication = application;

      expect(identical(first, second), isFalse);
      expect(identical(firstApplication, secondApplication), isFalse);
    });

    test('rejects applications without a registered factory', () async {
      final ApplicationId unknownId = ApplicationId('com.example.unknown');

      final ApplicationManifest unknownManifest = ApplicationManifest(
        id: unknownId,
        name: 'Unknown',
        version: '1.0.0',
        minimumFrameworkVersion: '0.1.0',
        runtime: ApplicationRuntimeKind.flutter,
      );

      final ApplicationLaunchContext unknownContext = ApplicationLaunchContext(
        applicationId: unknownId,
      );

      final TestServiceBroker unknownBroker = TestServiceBroker(
        applicationId: unknownId,
      );

      await expectLater(
        runtime.createInstance(
          manifest: unknownManifest,
          context: unknownContext,
          serviceBroker: unknownBroker,
        ),
        throwsStateError,
      );
    });

    test('rejects a non-Flutter manifest', () async {
      final ApplicationManifest webManifest = ApplicationManifest(
        id: applicationId,
        name: 'Web Application',
        version: '1.0.0',
        minimumFrameworkVersion: '0.1.0',
        runtime: ApplicationRuntimeKind.web,
        entryPoint: 'web/index.html',
      );

      await expectLater(
        runtime.createInstance(
          manifest: webManifest,
          context: launchContext,
          serviceBroker: broker,
        ),
        throwsArgumentError,
      );
    });

    test('rejects application identity mismatch', () async {
      final TestServiceBroker wrongBroker = TestServiceBroker(
        applicationId: ApplicationId('com.example.other'),
      );

      await expectLater(
        runtime.createInstance(
          manifest: manifest,
          context: launchContext,
          serviceBroker: wrongBroker,
        ),
        throwsArgumentError,
      );
    });

    test('executes application lifecycle callbacks', () async {
      final FlutterApplicationInstance instance = await runtime.createInstance(
        manifest: manifest,
        context: launchContext,
        serviceBroker: broker,
      ) as FlutterApplicationInstance;

      await instance.start();

      expect(instance.state, ApplicationLifecycleState.background);
      expect(application.lifecycleCalls, ['start']);

      await instance.setForeground();

      expect(instance.state, ApplicationLifecycleState.foreground);

      await instance.setBackground();

      expect(instance.state, ApplicationLifecycleState.background);

      await instance.stop();

      expect(instance.state, ApplicationLifecycleState.stopped);

      expect(application.lifecycleCalls, [
        'start',
        'foreground',
        'background',
        'stop',
      ]);
    });
    Future<void> testerPumpWidget(Widget widget) async {
      // This helper is intentionally not a WidgetTester.
      // The widget assertion is covered in the widget test below.
      expect(widget, isA<Widget>());
    }

    test('exposes the application widget', () async {
      final FlutterApplicationInstance instance = await runtime.createInstance(
        manifest: manifest,
        context: launchContext,
        serviceBroker: broker,
      ) as FlutterApplicationInstance;

      await testerPumpWidget(instance.widget);
    });

    test('does not allow invalid lifecycle transitions', () async {
      final FlutterApplicationInstance instance = await runtime.createInstance(
        manifest: manifest,
        context: launchContext,
        serviceBroker: broker,
      ) as FlutterApplicationInstance;

      await expectLater(instance.setForeground(), throwsStateError);
    });

    testWidgets('renders the application widget', (tester) async {
      final FlutterApplicationInstance instance = await runtime.createInstance(
        manifest: manifest,
        context: launchContext,
        serviceBroker: broker,
      ) as FlutterApplicationInstance;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: instance.widget,
        ),
      );

      expect(find.text('Hello from ${applicationId.value}'), findsOneWidget);
    });
  });
}
