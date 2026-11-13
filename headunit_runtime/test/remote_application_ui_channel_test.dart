import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_runtime/src/application/remote_application_rpc_session.dart';
import 'package:headunit_runtime/src/services/service_registry.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

void main() {
  group('Remote application UI channel', () {
    late ServiceRegistry registry;
    late RemoteApplicationRpcSession session;
    late HeadunitConnection connection;

    setUp(() async {
      registry = ServiceRegistry();
      final ApplicationLaunchContext context = ApplicationLaunchContext(
        applicationId: ApplicationId('com.example.ui_test'),
      );
      session = await RemoteApplicationRpcSession.bind(
        context: context,
        serviceBroker: registry.createBroker(context),
      );
      final RemoteApplicationEndpoint endpoint = session.endpoint;
      connection = await HeadunitConnection.connect(
        host: endpoint.host,
        port: endpoint.port,
        token: endpoint.token,
      );
      await session.waitUntilAuthenticated();
    });

    tearDown(() async {
      await connection.close();
      await session.dispose();
      registry.dispose();
    });

    test(
      'receives a standard page without opening the media channel',
      () async {
        final Future<HeadunitUiPage?> published = session.uiChannel.pages.first;
        await connection.ui.showPage(
          HeadunitUiPage(
            title: 'Reference page',
            body: HeadunitUiText(text: 'Visible without video'),
          ),
        );

        final HeadunitUiPage? page = await published;
        expect(page?.title, 'Reference page');
        expect(page?.body, isA<HeadunitUiText>());
        expect(session.uiChannel.currentPage?.title, 'Reference page');
      },
    );

    test(
      'routes a host action to the callback registered by the app',
      () async {
        final Completer<void> invoked = Completer<void>();
        await connection.ui.showPage(
          HeadunitUiPage(
            title: 'Actions',
            body: HeadunitUiButton(
              label: 'Tap me',
              action: HeadunitUiAction(
                id: 'test.tap',
                onInvoke: () {
                  if (!invoked.isCompleted) invoked.complete();
                },
              ),
            ),
          ),
        );

        session.uiChannel.sendAction('test.tap');
        await invoked.future.timeout(const Duration(seconds: 2));
        expect(invoked.isCompleted, isTrue);
      },
    );

    test('clears the current page', () async {
      await connection.ui.showPage(
        HeadunitUiPage(
          title: 'Temporary',
          body: HeadunitUiText(text: 'Temporary'),
        ),
      );
      final Future<HeadunitUiPage?> cleared = session.uiChannel.pages
          .firstWhere((HeadunitUiPage? page) => page == null);

      await connection.ui.clearPage();

      expect(await cleared, isNull);
      expect(session.uiChannel.currentPage, isNull);
    });
  });
}
