import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_auto_core/headunit/input/input_button.dart';

import 'input_driver.dart';

/// PC mouse input driver.
///
/// Maps:
/// - Mouse wheel up/down to configurable Android Auto buttons.
/// - Mouse side/back button to [mouseBackButton].
/// - Mouse side/forward button to [mouseForwardButton].
///
/// Side buttons send press and release events. Wheel movements send button taps.
///
/// The supplied InputButton instances must be bound to their channel before
/// they are used.
class PcInputDriver extends InputDriver {
  const PcInputDriver({
    super.key,
    required super.child,
    required this.scrollUpButton,
    required this.scrollDownButton,
    required this.mouseBackButton,
    required this.mouseForwardButton,
    this.scrollStep = 40,
  }) : assert(scrollStep > 0);

  final InputButton scrollUpButton;
  final InputButton scrollDownButton;
  final InputButton mouseBackButton;
  final InputButton mouseForwardButton;

  /// Accumulated vertical scroll distance required for one button tap.
  final double scrollStep;

  @override
  State<PcInputDriver> createState() => _PcInputDriverState();
}

class _PcInputDriverState extends State<PcInputDriver> {
  /// Last observed mouse button bitmask for each pointer.
  final Map<int, int> _buttonsByPointer = {};

  /// Side buttons currently pressed, tracked by pointer and mouse button flag.
  final Map<int, Map<int, InputButton>> _heldSideButtons = {};

  Future<void> _eventQueue = Future<void>.value();

  double _scrollRemainder = 0;
  bool _disposing = false;

  Map<int, InputButton> get _sideButtonBindings => {
    kBackMouseButton: widget.mouseBackButton,
    kForwardMouseButton: widget.mouseForwardButton,
  };

  void _enqueue(Future<void> Function() action) {
    _eventQueue = _eventQueue.then<void>((_) async {
      try {
        await action();
      } catch (error, stackTrace) {
        debugPrint('[PcInputDriver] Input failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (_disposing ||
        event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.mouse) {
      return;
    }

    _scrollRemainder += event.scrollDelta.dy;

    // Positive vertical delta means scrolling down.
    while (_scrollRemainder >= widget.scrollStep) {
      _scrollRemainder -= widget.scrollStep;
      _enqueue(() => widget.scrollDownButton.tap());
    }

    while (_scrollRemainder <= -widget.scrollStep) {
      _scrollRemainder += widget.scrollStep;
      _enqueue(() => widget.scrollUpButton.tap());
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _updateMouseButtons(event);
  }

  void _onPointerMove(PointerMoveEvent event) {
    // Also inspect moves in case the platform changes the mouse button
    // bitmask while a pointer is already down.
    _updateMouseButtons(event);
  }

  void _onPointerUp(PointerUpEvent event) {
    _updateMouseButtons(event);

    if (event.buttons == 0) {
      _buttonsByPointer.remove(event.pointer);
    }
  }

  void _updateMouseButtons(PointerEvent event) {
    if (_disposing || event.kind != PointerDeviceKind.mouse) return;

    final pointer = event.pointer;
    final previous = _buttonsByPointer[pointer] ?? 0;
    final current = event.buttons;

    for (final entry in _sideButtonBindings.entries) {
      final flag = entry.key;
      final button = entry.value;

      final wasDown = (previous & flag) != 0;
      final isDown = (current & flag) != 0;
      if (!wasDown && isDown) {
        // Record the button only after the protocol press succeeds.
        _enqueue(() async {
          await button.press();

          _heldSideButtons.putIfAbsent(pointer, () => {})[flag] = button;
        });
      } else if (wasDown && !isDown) {
        // A release is sent only if the press was successful.
        _enqueue(() async {
          final held = _heldSideButtons[pointer];
          final pressedButton = held?[flag];

          if (pressedButton == null) {
            return;
          }

          await pressedButton.release();

          held!.remove(flag);

          if (held.isEmpty) {
            _heldSideButtons.remove(pointer);
          }
        });
      }
    }

    _buttonsByPointer[pointer] = current;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _releasePointerButtons(event.pointer);
  }

  void _releasePointerButtons(int pointer) {
    _buttonsByPointer.remove(pointer);

    final held = _heldSideButtons.remove(pointer);
    if (held == null) return;

    for (final button in held.values) {
      _enqueue(button.release);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _onPointerSignal,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _disposing = true;

    // Release any side buttons that remain held.
    for (final pointer in _heldSideButtons.keys.toList()) {
      _releasePointerButtons(pointer);
    }

    unawaited(_eventQueue);

    super.dispose();
  }
}
