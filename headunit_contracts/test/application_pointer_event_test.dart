import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('ApplicationPointerEvent', () {
    test('round-trips normalized pointer data', () {
      final ApplicationPointerEvent event = ApplicationPointerEvent(
        pointerId: 3,
        phase: ApplicationPointerPhase.move,
        x: 0.125,
        y: 0.875,
        pressure: 0.6,
      );

      final ApplicationPointerEvent decoded =
          ApplicationPointerEvent.fromJson(event.toJson());

      expect(decoded.pointerId, event.pointerId);
      expect(decoded.phase, event.phase);
      expect(decoded.x, event.x);
      expect(decoded.y, event.y);
      expect(decoded.pressure, event.pressure);
    });

    test('rejects non-normalized coordinates', () {
      expect(
        () => ApplicationPointerEvent(
          pointerId: 0,
          phase: ApplicationPointerPhase.down,
          x: 1.1,
          y: 0.5,
        ),
        throwsArgumentError,
      );
    });
  });
}
