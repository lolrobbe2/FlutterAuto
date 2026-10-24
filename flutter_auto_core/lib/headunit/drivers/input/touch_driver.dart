import 'package:flutter/material.dart';
import 'input_driver.dart';
import '../../input/touch_input.dart';

/// Translates Flutter pointer events into Android Auto touch events.
///
/// Supports mouse input on desktop, single-touch, and multi-touch.
class TouchInputDriver extends InputDriver {
  const TouchInputDriver({
    super.key,
    required super.child,
    required this.touchInput,
    this.onError,
  });

  final TouchInput touchInput;

  /// Optional callback for errors while sending input events.
  final void Function(Object error, StackTrace stackTrace)? onError;

  @override
  State<TouchInputDriver> createState() => _TouchInputDriverState();
}

class _TouchInputDriverState extends State<TouchInputDriver> {
  final GlobalKey _surfaceKey = GlobalKey();

  final Set<int> _activePointers = <int>{};

  // Keep asynchronous touch events in the order Flutter reports them.
  Future<void> _eventQueue = Future<void>.value();

  void _enqueue(Future<void> Function() action) {
    _eventQueue = _eventQueue.then((_) async {
      try {
        await action();
      } catch (error, stackTrace) {
        _reportError(error, stackTrace);
      }
    });
  }

  void _reportError(Object error, StackTrace stackTrace) {
    final callback = widget.onError;

    if (callback != null) {
      callback(error, stackTrace);
      return;
    }

    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'TouchInputDriver',
        context: ErrorDescription(
          'while forwarding touch input to Android Auto',
        ),
      ),
    );
  }

  /// Converts local widget coordinates to the touchscreen's pixel space.
  /// Converts global pointer coordinates into the current display's
  /// touchscreen coordinate space.
  ///
  /// Uses the current RenderBox so fullscreen resizing and transforms
  /// are reflected in the coordinate mapping.
  _TouchCoordinates? _mapPosition(PointerEvent event) {
    final renderObject = _surfaceKey.currentContext?.findRenderObject();

    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }

    final size = renderObject.size;

    if (size.width <= 0 || size.height <= 0) {
      return null;
    }

    // Convert using the current render box, not a cached screen size.
    final position = renderObject.globalToLocal(event.position);

    // Ignore touches outside the actual driver surface.
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx >= size.width ||
        position.dy >= size.height) {
      return null;
    }

    final input = widget.touchInput;

    final x = (position.dx / size.width * input.width)
        .floor()
        .clamp(0, input.width - 1)
        .toInt();

    final y = (position.dy / size.height * input.height)
        .floor()
        .clamp(0, input.height - 1)
        .toInt();

    return _TouchCoordinates(x: x, y: y);
  }

  void _onPointerDown(PointerDownEvent event) {
    final coordinates = _mapPosition(event);
    if (coordinates == null) return;

    final input = widget.touchInput;
    final pointerId = event.pointer;

    _enqueue(() async {
      if (_activePointers.contains(pointerId)) return;

      if (_activePointers.isEmpty) {
        await input.press(
          x: coordinates.x,
          y: coordinates.y,
          pointerId: pointerId,
        );
      } else {
        await input.pointerDown(
          x: coordinates.x,
          y: coordinates.y,
          pointerId: pointerId,
        );
      }

      _activePointers.add(pointerId);
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    final coordinates = _mapPosition(event);
    if (coordinates == null) return;

    final input = widget.touchInput;
    final pointerId = event.pointer;

    _enqueue(() async {
      if (!_activePointers.contains(pointerId)) return;

      await input.drag(
        x: coordinates.x,
        y: coordinates.y,
        pointerId: pointerId,
      );
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    _finishPointer(event);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _finishPointer(event);
  }

  void _finishPointer(PointerEvent event) {
    final coordinates = _mapPosition(event);
    final input = widget.touchInput;
    final pointerId = event.pointer;

    _enqueue(() async {
      if (!_activePointers.contains(pointerId)) return;

      if (_activePointers.length == 1) {
        await input.release(
          pointerId: pointerId,
          x: coordinates?.x,
          y: coordinates?.y,
        );
      } else {
        await input.pointerUp(pointerId: pointerId);
      }

      _activePointers.remove(pointerId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: _surfaceKey,
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    // Release any active touches when leaving the screen.
    final input = widget.touchInput;

    _enqueue(() async {
      while (_activePointers.isNotEmpty) {
        final pointerId = _activePointers.last;

        try {
          if (_activePointers.length == 1) {
            await input.release(pointerId: pointerId);
          } else {
            await input.pointerUp(pointerId: pointerId);
          }
        } finally {
          _activePointers.remove(pointerId);
        }
      }
    });

    super.dispose();
  }
}

class _TouchCoordinates {
  const _TouchCoordinates({required this.x, required this.y});

  final int x;
  final int y;
}
