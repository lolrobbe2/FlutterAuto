import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_runtime/headunit_runtime.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

import '../support/test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('External application shell UI', () {
    late HeadunitRuntime runtime;
    late _FakeExternalProcessLauncher processLauncher;
    late ApplicationId applicationId;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      runtime = HeadunitRuntime(audioService: FakeAudioService());
      await runtime.initialize();
      processLauncher = _FakeExternalProcessLauncher();
      applicationId = ApplicationId('com.example.shell_ui');

      final ApplicationManager manager = runtime.applicationManager;
      final FlutterApplicationRuntime flutterRuntime =
          FlutterApplicationRuntime(processLauncher: processLauncher);
      final ApplicationManifest manifest = ApplicationManifest(
        id: applicationId,
        name: 'Shell UI test',
        version: '1.0.0',
        minimumFrameworkVersion: '0.1.0',
        runtime: ApplicationRuntimeKind.flutter,
      );
      final FlutterApplicationTarget target = FlutterApplicationTarget(
        platform: FlutterApplicationPlatform.windows,
        architecture: 'x64',
        bundlePath: 'artifacts/windows/x64',
        entryPoint: 'shell_ui.exe',
      );
      final FlutterApplicationPackageManifest packageManifest =
          FlutterApplicationPackageManifest(
            application: manifest,
            targets: <FlutterApplicationTarget>[target],
          );
      final Directory directory = Directory.systemTemp;
      final InstalledFlutterApplication installed = InstalledFlutterApplication(
        packageManifest: packageManifest,
        target: target,
        applicationDirectory: directory,
        bundleDirectory: directory,
        entryPoint: File(
          '${directory.path}${Platform.pathSeparator}shell_ui.exe',
        ),
      );

      flutterRuntime.registerInstalledApplication(installed);
      manager.registerRuntime(flutterRuntime);
      manager.registerApplication(
        ApplicationRegistration(
          manifest: manifest,
          grantedCapabilities: const <CapabilityId>[],
        ),
      );
    });

    tearDown(() async {
      try {
        await runtime.dispose();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'renders a child page in the shell and routes component actions',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HeadunitShell(
                applicationManager: runtime.applicationManager,
                homeBuilder: (BuildContext context) =>
                    const Center(child: Text('Headunit home')),
              ),
            ),
          ),
        );

        final ApplicationInstance? launched = await tester.runAsync(
          () => runtime.applicationManager
              .launch(applicationId)
              .timeout(const Duration(seconds: 8)),
        );
        expect(launched, isA<ExternalFlutterApplicationInstance>());
        expect(processLauncher.connection, isNotNull);

        final Completer<void> invoked = Completer<void>();
        await tester.runAsync(
          () => processLauncher.connection!.ui
              .showPage(
                HeadunitUiPage(
                  title: 'External page',
                  body: HeadunitUiColumn(
                    children: <HeadunitUiComponent>[
                      HeadunitUiText(text: 'Rendered by the headunit'),
                      HeadunitUiButton(
                        label: 'Run action',
                        action: HeadunitUiAction(
                          id: 'shell.run',
                          onInvoke: () {
                            if (!invoked.isCompleted) invoked.complete();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .timeout(const Duration(seconds: 8)),
        );
        await tester.pumpAndSettle();

        expect(find.text('External page'), findsOneWidget);
        expect(find.text('Rendered by the headunit'), findsOneWidget);
        // Observe the notification arriving at the child process.
        final Future<HeadunitHostEvent> receivedAction = processLauncher
            .connection!
            .notifications
            .firstWhere(
              (HeadunitHostEvent event) => event.method == 'ui.action',
            )
            .timeout(const Duration(seconds: 8));

        await tester.tap(find.text('Run action'));

        final HeadunitHostEvent? actionEvent = await tester.runAsync(
          () => receivedAction,
        );

        expect(actionEvent, isNotNull);
        expect(actionEvent!.parameters['actionId'], 'shell.run');

        // Now verify that the SDK invokes the application-local callback.
        await tester.runAsync(
          () => invoked.future.timeout(const Duration(seconds: 8)),
        );

        expect(invoked.isCompleted, isTrue);

        // Stop the child while runAsync is active. Its graceful-shutdown path
        // closes a real TCP socket and completes the fake process exit future.
        await tester.runAsync(
          () => runtime.applicationManager
              .stop(applicationId)
              .timeout(const Duration(seconds: 8)),
        );
      },
    );
  });
}

class _FakeExternalProcessLauncher implements ApplicationProcessLauncher {
  HeadunitConnection? connection;
  _FakeExternalProcessHandle? process;

  @override
  Future<ApplicationProcessHandle> launch({
    required InstalledFlutterApplication application,
    required RemoteApplicationEndpoint endpoint,
  }) async {
    final HeadunitConnection connected = await HeadunitConnection.connect(
      host: endpoint.host,
      port: endpoint.port,
      mediaPort: endpoint.mediaPort,
      token: endpoint.token,
    );
    final _FakeExternalProcessHandle handle = _FakeExternalProcessHandle(
      connected,
    );
    connection = connected;
    process = handle;
    return handle;
  }
}

class _FakeExternalProcessHandle implements ApplicationProcessHandle {
  final Completer<int> _exitCode = Completer<int>();
  final HeadunitConnection _connection;
  late final StreamSubscription<HeadunitHostEvent> _notifications;

  _FakeExternalProcessHandle(this._connection) {
    _notifications = _connection.notifications.listen((
      HeadunitHostEvent event,
    ) {
      if (event.method == 'application.lifecycle' &&
          event.parameters['state'] == 'stopping') {
        unawaited(finish(0));
      }
    });
  }

  @override
  int get pid => 90210;

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  bool kill() {
    unawaited(finish(137));
    return true;
  }

  Future<void> finish(int code) async {
    if (_exitCode.isCompleted) return;
    await _notifications.cancel();
    await _connection.close();
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }
}
