/// Type of pointer transition delivered from the headunit surface to an app.
enum ApplicationPointerPhase { down, move, up, cancel }

/// A pointer event in normalized application-surface coordinates.
///
/// Coordinates are in the inclusive range 0..1, independent of display
/// resolution. Pointer IDs allow multiple simultaneous touch contacts.
class ApplicationPointerEvent {
  final int pointerId;
  final ApplicationPointerPhase phase;
  final double x;
  final double y;
  final double? pressure;

  ApplicationPointerEvent({
    required this.pointerId,
    required this.phase,
    required this.x,
    required this.y,
    this.pressure,
  }) {
    if (pointerId < 0) {
      throw ArgumentError.value(pointerId, 'pointerId');
    }
    if (!x.isFinite || x < 0 || x > 1) {
      throw ArgumentError.value(x, 'x', 'Must be a normalized coordinate.');
    }
    if (!y.isFinite || y < 0 || y > 1) {
      throw ArgumentError.value(y, 'y', 'Must be a normalized coordinate.');
    }
    final double? value = pressure;
    if (value != null && (!value.isFinite || value < 0 || value > 1)) {
      throw ArgumentError.value(value, 'pressure');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'pointerId': pointerId,
    'phase': phase.name,
    'x': x,
    'y': y,
    if (pressure != null) 'pressure': pressure,
  };

  factory ApplicationPointerEvent.fromJson(Map<String, Object?> json) {
    final Object? rawPointerId = json['pointerId'];
    final Object? rawPhase = json['phase'];
    final Object? rawX = json['x'];
    final Object? rawY = json['y'];
    final Object? rawPressure = json['pressure'];

    if (rawPointerId is! int ||
        rawPhase is! String ||
        rawX is! num ||
        rawY is! num ||
        (rawPressure != null && rawPressure is! num)) {
      throw const FormatException('Invalid application pointer event.');
    }

    final ApplicationPointerPhase phase = switch (rawPhase) {
      'down' => ApplicationPointerPhase.down,
      'move' => ApplicationPointerPhase.move,
      'up' => ApplicationPointerPhase.up,
      'cancel' => ApplicationPointerPhase.cancel,
      _ => throw const FormatException('Unknown application pointer phase.'),
    };

    return ApplicationPointerEvent(
      pointerId: rawPointerId,
      phase: phase,
      x: rawX.toDouble(),
      y: rawY.toDouble(),
      // The explicit type test is needed because the nullable validation
      // expression above does not promote rawPressure after the if statement.
      pressure: rawPressure is num ? rawPressure.toDouble() : null,
    );
  }
}
