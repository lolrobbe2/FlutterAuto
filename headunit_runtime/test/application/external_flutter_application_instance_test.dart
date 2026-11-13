import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_runtime/headunit_runtime.dart';
import 'package:headunit_runtime/src/services/service_registry.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

void main() {
  group('ExternalFlutterApplicationInstance', () {
    late ServiceRegistry registry;
    late ApplicationId applicationId;
    late _FakeProcessLauncher launcher;
    late ExternalFlutterApplicationInstance instance;

    setUp(() async {
      applicationId = ApplicationId('com.example.external_test');
      registry = ServiceRegistry();
      launcher = _FakeProcessLauncher();

      final ApplicationLaunchContext context = ApplicationLaunchContext(
        applicationId: applicationId,
      );
      final ApplicationManifest manifest = ApplicationManifest(
        id: applicationId,
        name: 'External test',
        version: '1.0.0',
        minimumFrameworkVersion: '0.1.0',
        runtime: ApplicationRuntimeKind.flutter,
      );
      final FlutterApplicationTarget target = FlutterApplicationTarget(
        platform: FlutterApplicationPlatform.windows,
        architecture: 'x64',
        bundlePath: 'artifacts/windows/x64',
        entryPoint: 'example.exe',
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
          '${directory.path}${Platform.pathSeparator}example.exe',
        ),
      );

      instance = ExternalFlutterApplicationInstance(
        id: applicationId,
        context: context,
        serviceBroker: registry.createBroker(context),
        installedApplication: installed,
        processLauncher: launcher,
        startupTimeout: const Duration(seconds: 3),
        gracefulShutdownTimeout: const Duration(seconds: 1),
      );
    });

    tearDown(() async {
      await instance.stop();
      registry.dispose();
    });

    test(
      'starts after authentication without requiring a media connection',
      () async {
        await instance.start();

        expect(instance.state, ApplicationLifecycleState.background);
        expect(instance.processId, 4242);
        expect(instance.mediaConnection.value, isNull);
        expect(launcher.connection, isNotNull);
      },
    );

    test(
      'exposes UI pages and routes their actions through the shell',
      () async {
        await instance.start();
        final Completer<void> actionInvoked = Completer<void>();
        await launcher.connection!.ui.showPage(
          HeadunitUiPage(
            title: 'Shell page',
            body: HeadunitUiButton(
              label: 'Activate',
              action: HeadunitUiAction(
                id: 'test.activate',
                onInvoke: () {
                  if (!actionInvoked.isCompleted) actionInvoked.complete();
                },
              ),
            ),
          ),
        );
        expect(instance.uiPage.value?.title, 'Shell page');
        instance.sendUiAction('test.activate');
        await actionInvoked.future.timeout(const Duration(seconds: 2));
        expect(actionInvoked.isCompleted, isTrue);
      },
    );

    test(
      'forwards pointer events over the authenticated SDK connection',
      () async {
        await instance.start();
        final Future<ApplicationPointerEvent> received =
            launcher.connection!.pointerEvents.first;

        instance.sendPointerEvent(
          ApplicationPointerEvent(
            pointerId: 4,
            phase: ApplicationPointerPhase.down,
            x: 0.2,
            y: 0.8,
          ),
        );

        final ApplicationPointerEvent event = await received;
        expect(event.pointerId, 4);
        expect(event.phase, ApplicationPointerPhase.down);
        expect(event.x, 0.2);
        expect(event.y, 0.8);
      },
    );

    test(
      'transitions to stopped and closes the child process on stop',
      () async {
        await instance.start();
        await instance.stop();

        expect(instance.state, ApplicationLifecycleState.stopped);
        expect(instance.isProcessRunning, isFalse);
        expect(instance.mediaConnection.value, isNull);
      },
    );

    test('reports an unexpected child process exit as failed', () async {
      await instance.start();
      final Future<ApplicationLifecycleEvent> failed = instance.lifecycleEvents
          .firstWhere(
            (ApplicationLifecycleEvent event) =>
                event.currentState == ApplicationLifecycleState.failed,
          );

      await launcher.process!.finish(17);

      final ApplicationLifecycleEvent event = await failed.timeout(
        const Duration(seconds: 2),
      );
      expect(event.reason, contains('17'));
      expect(instance.state, ApplicationLifecycleState.failed);
      expect(instance.isProcessRunning, isFalse);
    });
  });
}

class _FakeProcessLauncher implements ApplicationProcessLauncher {
  HeadunitConnection? connection;
  _FakeProcessHandle? process;

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

    final _FakeProcessHandle handle = _FakeProcessHandle();
    handle.attach(connected);
    connection = connected;
    process = handle;
    return handle;
  }
}

class _FakeProcessHandle implements ApplicationProcessHandle {
  final Completer<int> _exit = Completer<int>();
  final StreamController<List<int>> _stdout =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderr =
      StreamController<List<int>>.broadcast();

  HeadunitConnection? _connection;
  StreamSubscription<HeadunitHostEvent>? _notifications;

  void attach(HeadunitConnection connection) {
    _connection = connection;
    _notifications = connection.notifications.listen((HeadunitHostEvent event) {
      if (event.method == 'application.lifecycle' &&
          event.parameters['state'] == 'stopping') {
        unawaited(finish(0));
      }
    });
  }

  @override
  int get pid => 4242;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill() {
    unawaited(finish(137));
    return true;
  }

  Future<void> finish(int code) async {
    if (_exit.isCompleted) {
      return;
    }
    await _notifications?.cancel();
    _notifications = null;
    final HeadunitConnection? connection = _connection;
    _connection = null;
    await connection?.close();
    await _stdout.close();
    await _stderr.close();
    if (!_exit.isCompleted) {
      _exit.complete(code);
    }
  }
}
