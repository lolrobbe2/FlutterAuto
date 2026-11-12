import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:headunit_runtime/headunit_runtime.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

import '../support/test_fixtures.dart';

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

void main() {
  group('HeadunitShell', () {
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

        flutterRuntime.registerApplication(
          id: counterId,
          factory: CounterApplication.new,
        );

        flutterRuntime.registerApplication(
          id: secondId,
          factory: () => const LabelApplication('Second application'),
        );

        manager.registerRuntime(flutterRuntime);

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
          ),
        );

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
                    Expanded(child: applicationSurface),
                  ],
                );
              },
            ),
          ),
        );

        expect(find.text('System UI'), findsOneWidget);
        expect(find.text('Home screen'), findsOneWidget);

        // Launch the counter application.
        await manager.launch(counterId);
        await tester.pump();

        expect(find.text('Counter: 0'), findsOneWidget);

        // Change its internal state.
        await tester.tap(find.byKey(const ValueKey<String>('counter')));
        await tester.pump();

        expect(find.text('Counter: 1'), findsOneWidget);

        // Launch another application.
        await manager.launch(secondId);
        await tester.pump();

        expect(find.text('Second application'), findsOneWidget);

        // Counter is hidden, but remains mounted.
        expect(
          find.text('Counter: 1', skipOffstage: false),
          findsOneWidget,
        );

        // Return to the original application.
        await manager.setForeground(counterId);
        await tester.pump();

        expect(find.text('Counter: 1'), findsOneWidget);

        // Background the application and return to home.
        await manager.setBackground(counterId);
        await tester.pump();

        expect(find.text('Home screen'), findsOneWidget);

        expect(find.text('System UI'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.dispose();
      },
    );
  });
}