import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_contracts/headunit_contracts.dart';

void main() {
  group('ApplicationLifecycleState', () {
    test('stopped can only transition to starting', () {
      expect(
        ApplicationLifecycleState.stopped.canTransitionTo(
          ApplicationLifecycleState.starting,
        ),
        isTrue,
      );

      expect(
        ApplicationLifecycleState.stopped.canTransitionTo(
          ApplicationLifecycleState.foreground,
        ),
        isFalse,
      );

      expect(
        ApplicationLifecycleState.stopped.canTransitionTo(
          ApplicationLifecycleState.background,
        ),
        isFalse,
      );
    });

    test('starting can transition to foreground or background', () {
      expect(
        ApplicationLifecycleState.starting.canTransitionTo(
          ApplicationLifecycleState.foreground,
        ),
        isTrue,
      );

      expect(
        ApplicationLifecycleState.starting.canTransitionTo(
          ApplicationLifecycleState.background,
        ),
        isTrue,
      );

      expect(
        ApplicationLifecycleState.starting.canTransitionTo(
          ApplicationLifecycleState.failed,
        ),
        isTrue,
      );
    });

    test('foreground and background can switch between each other', () {
      expect(
        ApplicationLifecycleState.foreground.canTransitionTo(
          ApplicationLifecycleState.background,
        ),
        isTrue,
      );

      expect(
        ApplicationLifecycleState.background.canTransitionTo(
          ApplicationLifecycleState.foreground,
        ),
        isTrue,
      );
    });

    test('foreground cannot directly transition to stopped', () {
      expect(
        ApplicationLifecycleState.foreground.canTransitionTo(
          ApplicationLifecycleState.stopped,
        ),
        isFalse,
      );
    });

    test('stopping can transition to stopped', () {
      expect(
        ApplicationLifecycleState.stopping.canTransitionTo(
          ApplicationLifecycleState.stopped,
        ),
        isTrue,
      );
    });

    test('failed can transition to stopped or starting', () {
      expect(
        ApplicationLifecycleState.failed.canTransitionTo(
          ApplicationLifecycleState.stopped,
        ),
        isTrue,
      );

      expect(
        ApplicationLifecycleState.failed.canTransitionTo(
          ApplicationLifecycleState.starting,
        ),
        isTrue,
      );
    });
    test('background can transition to suspended', () {
      expect(
        ApplicationLifecycleState.background.canTransitionTo(
          ApplicationLifecycleState.suspended,
        ),
        isTrue,
      );
    });

    test('suspended can transition back to background', () {
      expect(
        ApplicationLifecycleState.suspended.canTransitionTo(
          ApplicationLifecycleState.background,
        ),
        isTrue,
      );
    });

    test('suspended cannot transition directly to foreground', () {
      expect(
        ApplicationLifecycleState.suspended.canTransitionTo(
          ApplicationLifecycleState.foreground,
        ),
        isFalse,
      );
    });

    test('suspended can be stopped', () {
      expect(
        ApplicationLifecycleState.suspended.canTransitionTo(
          ApplicationLifecycleState.stopping,
        ),
        isTrue,
      );
    });
  });
}
