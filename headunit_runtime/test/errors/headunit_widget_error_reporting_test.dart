import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:headunit_runtime/headunit_runtime.dart';

import '../support/test_fixtures.dart';

void main() {
  testWidgets(
    'reports exceptions thrown while building widgets',
    (WidgetTester tester) async {
      final FlutterExceptionHandler? previousHandler =
          FlutterError.onError;

      // Prevent the test binding from treating the expected widget
      // exception as an unhandled test failure.
      FlutterError.onError = (_) {};

      final HeadunitRuntime runtime = HeadunitRuntime(
        audioService: FakeAudioService(),
      );

      try {
        await runtime.initialize();

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

        final List<ApplicationError> reportedErrors =
            runtime.errorReporter.recentErrors
                .where(
                  (ApplicationError error) =>
                      identical(error.error, widgetError) &&
                      error.source == ApplicationErrorSource.widget,
                )
                .toList();

        expect(reportedErrors, hasLength(1));
        expect(reportedErrors.single.applicationId, isNull);
        expect(reportedErrors.single.stackTrace, isNotNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.dispose();

        FlutterError.onError = previousHandler;
      }
    },
  );
}