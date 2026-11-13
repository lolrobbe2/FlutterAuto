import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_runtime/headunit_runtime.dart';
import 'package:headunit_runtime/src/ui/headunit_ui_renderer.dart';
import 'package:headunit_runtime/src/ui/headunit_ui_theme.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

void main() {
  testWidgets('renders standard components and dispatches their action IDs', (
    WidgetTester tester,
  ) async {
    String? invokedAction;
    final HeadunitUiPage page = HeadunitUiPage(
      title: 'Music',
      subtitle: 'Reference UI',
      body: HeadunitUiColumn(
        children: <HeadunitUiComponent>[
          HeadunitUiText(
            text: 'Recently played',
            style: HeadunitUiTextStyle.title,
          ),
          HeadunitUiButton(
            label: 'Open playlist',
            action: HeadunitUiAction(id: 'playlist.open'),
          ),
          HeadunitUiList(
            items: <HeadunitUiListItem>[
              HeadunitUiListItem(
                id: 'track-1',
                title: 'Midnight Drive',
                action: HeadunitUiAction(id: 'track.open'),
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: const <ThemeExtension<dynamic>>[HeadunitUiTheme()],
        ),
        home: Scaffold(
          body: HeadunitUiRenderer(
            page: page,
            onAction: (String actionId) => invokedAction = actionId,
          ),
        ),
      ),
    );

    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Recently played'), findsOneWidget);
    await tester.tap(find.text('Open playlist'));
    expect(invokedAction, 'playlist.open');
    await tester.tap(find.text('Midnight Drive'));
    expect(invokedAction, 'track.open');
  });
}
