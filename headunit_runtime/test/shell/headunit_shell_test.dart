import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_runtime/headunit_runtime.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

import '../support/test_fixtures.dart';

// -----------------------------------------------------------------------------
// Test applications
// -----------------------------------------------------------------------------

class CounterApplication extends HeadunitApplication {
  @override
  Widget build(HeadunitApplicationContext context) {
    return const CounterWidget();
  }
}

class CounterWidget extends StatefulWidget {
  const CounterWidget({super.key});

  @override
  State<CounterWidget> createState() => _CounterWidgetState();
}

class _CounterWidgetState extends State<CounterWidget> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey<String>('counter'),
      onTap: () {
        setState(() {
          _count++;
        });
      },
      child: Text('Counter: $_count'),
    );
  }
}

class LabelApplication extends HeadunitApplication {
  final String label;

  const LabelApplication(this.label);

  @override
  Widget build(HeadunitApplicationContext context) {
    return Text(label);
  }
}

// -----------------------------------------------------------------------------
// Test helpers
// -----------------------------------------------------------------------------

Future<HeadunitRuntime> createInitializedRuntime() async {
  final HeadunitRuntime runtime = HeadunitRuntime(
    audioService: FakeAudioService(),
  );

  await runtime.initialize();

  return runtime;
}

void registerTestApplication({
  required ApplicationManager manager,
  required FlutterApplicationRuntime runtime,
  required ApplicationId id,
  required String name,
  required HeadunitApplication Function() factory,
  required ApplicationBackgroundPolicy backgroundPolicy,
}) {
  runtime.registerApplication(id: id, factory: factory);

  manager.registerApplication(
    ApplicationRegistration(
      manifest: ApplicationManifest(
        id: id,
        name: name,
        version: '1.0.0',
        minimumFrameworkVersion: '0.1.0',
        runtime: ApplicationRuntimeKind.flutter,
      ),
      grantedCapabilities: [],
      backgroundPolicy: backgroundPolicy,
    ),
  );
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

void main() {
  group('HeadunitShell', () {
    // -------------------------------------------------------------------------
    // Home screen
    // -------------------------------------------------------------------------

    testWidgets('displays the home screen when no application is foreground', (
      WidgetTester tester,
    ) async {
      final HeadunitRuntime runtime = await createInitializedRuntime();

      addTearDown(() async {
        await runtime.dispose();
      });

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: HeadunitShell(
            applicationManager: runtime.applicationManager,
            homeBuilder: (BuildContext context) {
              return const Text('Home screen');
            },
          ),
        ),
      );

      expect(find.text('Home screen'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // keepMounted policy
    // -------------------------------------------------------------------------

    testWidgets(
      'switches between applications and preserves background UI state',
      (WidgetTester tester) async {
        final HeadunitRuntime runtime = await createInitializedRuntime();
        addTearDown(runtime.dispose);
        final ApplicationManager manager = runtime.applicationManager;

        final FlutterApplicationRuntime flutterRuntime =
            FlutterApplicationRuntime();

        final ApplicationId counterId = ApplicationId('com.example.counter');

        final ApplicationId secondId = ApplicationId('com.example.second');

        registerTestApplication(
          manager: manager,
          runtime: flutterRuntime,
          id: counterId,
          name: 'Counter',
          factory: CounterApplication.new,
          backgroundPolicy: ApplicationBackgroundPolicy.keepMounted,
        );

        registerTestApplication(
          manager: manager,
          runtime: flutterRuntime,
          id: secondId,
          name: 'Second application',
          factory: () => const LabelApplication('Second application'),
          backgroundPolicy: ApplicationBackgroundPolicy.keepMounted,
        );

        manager.registerRuntime(flutterRuntime);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: HeadunitShell(
              applicationManager: manager,
              homeBuilder: (BuildContext context) {
                return const Text('Home screen');
              },
              layoutBuilder: (BuildContext context, Widget applicationSurface) {
                return Column(
                  children: [
                    const Text('System UI'),
                    Expanded(child: applicationSurface),
                  ],
                );
              },
            ),
          ),
        );

        expect(find.text('System UI'), findsOneWidget);
        expect(find.text('Home screen'), findsOneWidget);

        // Launch Counter.
        final ApplicationInstance counterInstance = await manager.launch(
          counterId,
        );

        await tester.pumpAndSettle();

        expect(find.text('Counter: 0'), findsOneWidget);
        expect(counterInstance.state, ApplicationLifecycleState.foreground);

        // Change the Counter widget state.
        await tester.tap(find.byKey(const ValueKey<String>('counter')));

        await tester.pumpAndSettle();

        expect(find.text('Counter: 1'), findsOneWidget);

        // Launch the second application.
        await manager.launch(secondId);

        await tester.pumpAndSettle();

        expect(find.text('Second application'), findsOneWidget);
        expect(counterInstance.state, ApplicationLifecycleState.background);

        // Counter remains mounted, but hidden.
        expect(find.text('Counter: 1', skipOffstage: false), findsOneWidget);

        expect(find.byType(CounterWidget, skipOffstage: false), findsOneWidget);

        // Return to Counter.
        await manager.setForeground(counterId);

        await tester.pumpAndSettle();

        expect(find.text('Counter: 1'), findsOneWidget);
        expect(counterInstance.state, ApplicationLifecycleState.foreground);

        // Background Counter and return to the home screen.
        await manager.setBackground(counterId);

        await tester.pumpAndSettle();

        expect(find.text('Home screen'), findsOneWidget);
        expect(find.text('System UI'), findsOneWidget);

        // Counter remains mounted while the home screen is displayed.
        expect(find.text('Counter: 1', skipOffstage: false), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // suspend policy
    // -------------------------------------------------------------------------

    testWidgets(
      'suspending an application removes its UI but preserves its instance',
      (WidgetTester tester) async {
        final HeadunitRuntime runtime = await createInitializedRuntime();
        addTearDown(runtime.dispose);
        final ApplicationManager manager = runtime.applicationManager;

        final FlutterApplicationRuntime flutterRuntime =
            FlutterApplicationRuntime();

        final ApplicationId counterId = ApplicationId('com.example.counter');

        final ApplicationId secondId = ApplicationId('com.example.second');

        registerTestApplication(
          manager: manager,
          runtime: flutterRuntime,
          id: counterId,
          name: 'Counter',
          factory: CounterApplication.new,
          backgroundPolicy: ApplicationBackgroundPolicy.suspend,
        );

        registerTestApplication(
          manager: manager,
          runtime: flutterRuntime,
          id: secondId,
          name: 'Second application',
          factory: () => const LabelApplication('Second application'),
          backgroundPolicy: ApplicationBackgroundPolicy.keepMounted,
        );

        manager.registerRuntime(flutterRuntime);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: HeadunitShell(
              applicationManager: manager,
              homeBuilder: (BuildContext context) {
                return const Text('Home screen');
              },
            ),
          ),
        );

        expect(find.text('Home screen'), findsOneWidget);

        // Launch Counter.
        final ApplicationInstance originalInstance = await manager.launch(
          counterId,
        );

        await tester.pumpAndSettle();

        expect(find.text('Counter: 0'), findsOneWidget);

        // Change its widget state.
        await tester.tap(find.byKey(const ValueKey<String>('counter')));

        await tester.pumpAndSettle();

        expect(find.text('Counter: 1'), findsOneWidget);

        // Launch another application.
        // Counter should be backgrounded and then suspended.
        await manager.launch(secondId);

        await tester.pumpAndSettle();

        expect(find.text('Second application'), findsOneWidget);
        expect(originalInstance.state, ApplicationLifecycleState.suspended);

        // Suspended application's widget is no longer mounted.
        expect(find.byType(CounterWidget, skipOffstage: false), findsNothing);

        // Its application instance still exists.
        expect(manager.getInstance(counterId), same(originalInstance));

        // Return to the suspended application.
        await manager.launch(counterId);

        await tester.pumpAndSettle();

        expect(originalInstance.state, ApplicationLifecycleState.foreground);

        // The same application instance was resumed.
        expect(manager.getInstance(counterId), same(originalInstance));

        // Its widget was recreated, so widget-local state resets.
        expect(find.text('Counter: 0'), findsOneWidget);
        expect(find.text('Counter: 1'), findsNothing);
      },
    );

    // -------------------------------------------------------------------------
    // Widget error reporting
    // -------------------------------------------------------------------------

    testWidgets(
      'reports exceptions thrown while building application widgets',
      (WidgetTester tester) async {
        final HeadunitRuntime runtime = await createInitializedRuntime();
        addTearDown(runtime.dispose);
        final StateError widgetError = StateError(
          'Application widget build failed.',
        );

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (BuildContext context) {
                throw widgetError;
              },
            ),
          ),
        );

        // Flutter's test binding receives the exception through the
        // original FlutterError.onError handler chained by the runtime.
        final Object? caughtException = tester.takeException();

        expect(caughtException, same(widgetError));

        final List<ApplicationError> reportedErrors = runtime
            .errorReporter
            .recentErrors
            .where(
              (ApplicationError error) =>
                  identical(error.error, widgetError) &&
                  error.source == ApplicationErrorSource.widget,
            )
            .toList();

        expect(reportedErrors, hasLength(1));

        final ApplicationError reportedError = reportedErrors.single;

        expect(reportedError.applicationId, isNull);
        expect(reportedError.source, ApplicationErrorSource.widget);
        expect(reportedError.severity, ApplicationErrorSeverity.error);
        expect(reportedError.error, same(widgetError));
        expect(reportedError.stackTrace, isNotNull);
        expect(
          reportedError.message,
          contains('Application widget build failed.'),
        );
      },
    );
  });
}
