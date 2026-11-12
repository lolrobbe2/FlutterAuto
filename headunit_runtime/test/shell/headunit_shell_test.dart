
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_contracts/headunit_contracts.dart';
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
// Tests
// -----------------------------------------------------------------------------

void main() {
  group('HeadunitShell', () {
    // -------------------------------------------------------------------------
    // Home screen
    // -------------------------------------------------------------------------

    testWidgets(
      'displays the home screen when no application is foreground',
      (WidgetTester tester) async {
        final HeadunitRuntime runtime = HeadunitRuntime(
          audioService: FakeAudioService(),
        );

        await runtime.initialize();

        final ApplicationManager manager = runtime.applicationManager;

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

        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.dispose();
      },
    );

    // -------------------------------------------------------------------------
    // keepMounted policy
    // -------------------------------------------------------------------------

    testWidgets(
      'switches between applications and preserves background UI state',
      (WidgetTester tester) async {
        final HeadunitRuntime runtime = HeadunitRuntime(
          audioService: FakeAudioService(),
        );

        await runtime.initialize();

        final ApplicationManager manager = runtime.applicationManager;

        final FlutterApplicationRuntime flutterRuntime =
            FlutterApplicationRuntime();

        final ApplicationId counterId =
            ApplicationId('com.example.counter');

        final ApplicationId secondId =
            ApplicationId('com.example.second');

        // Register application factories.
        flutterRuntime.registerApplication(
          id: counterId,
          factory: CounterApplication.new,
        );

        flutterRuntime.registerApplication(
          id: secondId,
          factory: () => const LabelApplication('Second application'),
        );

        manager.registerRuntime(flutterRuntime);

        // Register applications with the default keepMounted policy.
        manager.registerApplication(
          ApplicationRegistration(
            manifest: ApplicationManifest(
              id: counterId,
              name: 'Counter',
              version: '1.0.0',
              minimumFrameworkVersion: '0.1.0',
              runtime: ApplicationRuntimeKind.flutter,
            ),
            grantedCapabilities: [],
            backgroundPolicy: ApplicationBackgroundPolicy.keepMounted,
          ),
        );

        manager.registerApplication(
          ApplicationRegistration(
            manifest: ApplicationManifest(
              id: secondId,
              name: 'Second application',
              version: '1.0.0',
              minimumFrameworkVersion: '0.1.0',
              runtime: ApplicationRuntimeKind.flutter,
            ),
            grantedCapabilities: [],
            backgroundPolicy: ApplicationBackgroundPolicy.keepMounted,
          ),
        );

        // Mount the shell.
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: HeadunitShell(
              applicationManager: manager,
              homeBuilder: (BuildContext context) {
                return const Text('Home screen');
              },
              layoutBuilder: (
                BuildContext context,
                Widget applicationSurface,
              ) {
                return Column(
                  children: [
                    const Text('System UI'),
                    Expanded(
                      child: applicationSurface,
                    ),
                  ],
                );
              },
            ),
          ),
        );

        expect(find.text('System UI'), findsOneWidget);
        expect(find.text('Home screen'), findsOneWidget);

        // Launch Counter.
        final ApplicationInstance counterInstance =
            await manager.launch(counterId);

        await tester.pumpAndSettle();

        expect(find.text('Counter: 0'), findsOneWidget);
        expect(
          counterInstance.state,
          ApplicationLifecycleState.foreground,
        );

        // Change the Counter widget state.
        await tester.tap(
          find.byKey(const ValueKey<String>('counter')),
        );

        await tester.pumpAndSettle();

        expect(find.text('Counter: 1'), findsOneWidget);

        // Launch the second application.
        await manager.launch(secondId);

        await tester.pumpAndSettle();

        expect(find.text('Second application'), findsOneWidget);

        expect(
          counterInstance.state,
          ApplicationLifecycleState.background,
        );

        // Counter remains mounted, but hidden.
        expect(
          find.text('Counter: 1', skipOffstage: false),
          findsOneWidget,
        );

        expect(
          find.byType(CounterWidget, skipOffstage: false),
          findsOneWidget,
        );

        // Return to Counter.
        await manager.setForeground(counterId);

        await tester.pumpAndSettle();

        expect(find.text('Counter: 1'), findsOneWidget);

        expect(
          counterInstance.state,
          ApplicationLifecycleState.foreground,
        );

        // Background Counter and return to the home screen.
        await manager.setBackground(counterId);

        await tester.pumpAndSettle();

        expect(find.text('Home screen'), findsOneWidget);
        expect(find.text('System UI'), findsOneWidget);

        // Counter remains mounted while the home screen is displayed.
        expect(
          find.text('Counter: 1', skipOffstage: false),
          findsOneWidget,
        );

        // Cleanup.
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.dispose();
      },
    );

    // -------------------------------------------------------------------------
    // suspend policy
    // -------------------------------------------------------------------------

    testWidgets(
      'suspending an application removes its UI but preserves its instance',
      (WidgetTester tester) async {
        final HeadunitRuntime runtime = HeadunitRuntime(
          audioService: FakeAudioService(),
        );

        await runtime.initialize();

        final ApplicationManager manager = runtime.applicationManager;

        final FlutterApplicationRuntime flutterRuntime =
            FlutterApplicationRuntime();

        final ApplicationId counterId =
            ApplicationId('com.example.counter');

        final ApplicationId secondId =
            ApplicationId('com.example.second');

        // Register application factories.
        flutterRuntime.registerApplication(
          id: counterId,
          factory: CounterApplication.new,
        );

        flutterRuntime.registerApplication(
          id: secondId,
          factory: () => const LabelApplication('Second application'),
        );

        manager.registerRuntime(flutterRuntime);

        // Counter uses the suspend policy.
        manager.registerApplication(
          ApplicationRegistration(
            manifest: ApplicationManifest(
              id: counterId,
              name: 'Counter',
              version: '1.0.0',
              minimumFrameworkVersion: '0.1.0',
              runtime: ApplicationRuntimeKind.flutter,
            ),
            grantedCapabilities: [],
            backgroundPolicy: ApplicationBackgroundPolicy.suspend,
          ),
        );

        // Second application uses keepMounted.
        manager.registerApplication(
          ApplicationRegistration(
            manifest: ApplicationManifest(
              id: secondId,
              name: 'Second application',
              version: '1.0.0',
              minimumFrameworkVersion: '0.1.0',
              runtime: ApplicationRuntimeKind.flutter,
            ),
            grantedCapabilities: [],
            backgroundPolicy: ApplicationBackgroundPolicy.keepMounted,
          ),
        );

        // Mount the shell.
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
        final ApplicationInstance originalInstance =
            await manager.launch(counterId);

        await tester.pumpAndSettle();

        expect(find.text('Counter: 0'), findsOneWidget);

        // Change its widget state.
        await tester.tap(
          find.byKey(const ValueKey<String>('counter')),
        );

        await tester.pumpAndSettle();

        expect(find.text('Counter: 1'), findsOneWidget);

        // Launch another application.
        // Counter should be backgrounded and then suspended.
        await manager.launch(secondId);

        await tester.pumpAndSettle();

        expect(find.text('Second application'), findsOneWidget);

        expect(
          originalInstance.state,
          ApplicationLifecycleState.suspended,
        );

        // Suspended application's widget is no longer mounted.
        expect(
          find.byType(CounterWidget, skipOffstage: false),
          findsNothing,
        );

        // However, its application instance still exists.
        expect(
          manager.getInstance(counterId),
          same(originalInstance),
        );

        // Return to the suspended application.
        await manager.launch(counterId);

        await tester.pumpAndSettle();

        expect(
          originalInstance.state,
          ApplicationLifecycleState.foreground,
        );

        // The same application instance was resumed.
        expect(
          manager.getInstance(counterId),
          same(originalInstance),
        );

        // Its widget was recreated, so the widget-local counter resets.
        expect(find.text('Counter: 0'), findsOneWidget);

        expect(find.text('Counter: 1'), findsNothing);

        // Cleanup.
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.dispose();
      },
    );
  });
}
