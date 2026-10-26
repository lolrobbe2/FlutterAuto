import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_auto_core/headunit/input/input_button.dart';

import 'input_driver.dart';

/// The electrical level reported by a GPIO input.
enum GpioLevel {
  low,
  high,
}

/// A GPIO input transition reported by the platform GPIO reader.
class GpioInputEvent {
  const GpioInputEvent({
    required this.gpioInputCode,
    required this.level,
  });

  /// GPIO pin number or input code supplied by the GPIO backend.
  final int gpioInputCode;

  /// Current electrical level of the input.
  final GpioLevel level;
}

/// Associates a GPIO input with an existing InputButton.
///
/// Defaults to active-low, which is common for buttons wired using pull-ups.
class GpioButtonBinding {
  const GpioButtonBinding({
    required this.gpioInputCode,
    required this.buttonInput,
    this.activeLevel = GpioLevel.low,
  });

  final int gpioInputCode;
  final InputButton buttonInput;

  /// The electrical level that means "pressed".
  final GpioLevel activeLevel;
}

/// A widget that maps GPIO input events to Android Auto button inputs.
///
/// Each GPIO input code is associated with an [InputButton]. When the GPIO
/// input becomes active, the corresponding button is pressed. When it becomes
/// inactive, the button is released.
///
/// By default, GPIO inputs are active-low ([GpioLevel.low]).
///
/// ## Example
///
/// ```dart
/// GpioInputDriver(
///   child: headunitScreen,
///   events: gpioController.events,
///   buttons: [
///     GpioButtonBinding(
///       gpioInputCode: 17,
///       buttonInput: InputButton(ButtonCode_Enum.HOME),
///     ),
///     GpioButtonBinding(
///       gpioInputCode: 27,
///       buttonInput: InputButton(ButtonCode_Enum.BACK),
///     ),
///     GpioButtonBinding(
///       gpioInputCode: 22,
///       buttonInput: InputButton(ButtonCode_Enum.DPAD_UP),
///       activeLevel: GpioLevel.high,
///     ),
///   ],
/// )
/// ```
///
/// The [events] stream must be provided by a platform-specific GPIO backend.
/// Each [GpioButtonBinding] associates a GPIO input code with the button to
/// trigger and optionally specifies the electrical level representing a press.
///
/// Ensure each [InputButton] is bound to its channel before GPIO events arrive.
class GpioInputDriver extends InputDriver {
  const GpioInputDriver({
    super.key,
    required super.child,
    required this.buttons,
    required this.events,
  });

  /// Each GPIO input code is matched to its corresponding InputButton.
  final List<GpioButtonBinding> buttons;

  /// Events produced by the platform-specific GPIO reader.
  final Stream<GpioInputEvent> events;

  @override
  State<GpioInputDriver> createState() => _GpioInputDriverState();
}

class _GpioInputDriverState extends State<GpioInputDriver> {
  final Map<int, GpioButtonBinding> _bindings = {};
  final Map<int, bool> _pressed = {};

  StreamSubscription<GpioInputEvent>? _subscription;

  /// Serializes events so fast GPIO transitions cannot overlap button sends.
  Future<void> _eventQueue = Future<void>.value();

  bool _disposing = false;

  @override
  void initState() {
    super.initState();
    _configureBindings();
    _subscribe();
  }

  void _configureBindings() {
    _bindings.clear();
    _pressed.clear();

    final buttonsSeen = <InputButton>{};

    for (final binding in widget.buttons) {
      if (_bindings.containsKey(binding.gpioInputCode)) {
        throw ArgumentError(
          'Duplicate GPIO input code: ${binding.gpioInputCode}',
        );
      }

      if (!buttonsSeen.add(binding.buttonInput)) {
        throw ArgumentError(
          'The same InputButton instance cannot be bound to multiple GPIO '
          'inputs. Create a separate InputButton for each mapping.',
        );
      }

      _bindings[binding.gpioInputCode] = binding;
      _pressed[binding.gpioInputCode] = false;
    }
  }

  void _subscribe() {
    _subscription = widget.events.listen(
      (event) {
        _eventQueue = _eventQueue
            .then<void>((_) => _handleEvent(event))
            .catchError((Object error, StackTrace stackTrace) {
              debugPrint(
                '[GpioInputDriver] Failed to process GPIO event: $error',
              );
            });
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[GpioInputDriver] GPIO stream error: $error');
      },
    );
  }

  Future<void> _handleEvent(GpioInputEvent event) async {
    if (_disposing) return;

    final binding = _bindings[event.gpioInputCode];

    // Ignore GPIO inputs that have no button mapping.
    if (binding == null) return;

    final isPressed = event.level == binding.activeLevel;
    final wasPressed = _pressed[event.gpioInputCode] ?? false;

    // Ignore repeated readings without a state transition.
    if (isPressed == wasPressed) return;

    if (isPressed) {
      await binding.buttonInput.press();
    } else {
      await binding.buttonInput.release();
    }

    _pressed[event.gpioInputCode] = isPressed;

    debugPrint(
      '[GpioInputDriver] GPIO ${event.gpioInputCode} '
      '${isPressed ? "pressed" : "released"} '
      '-> ${binding.buttonInput.buttonCode.name}',
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    _disposing = true;
    unawaited(_shutdown());
    super.dispose();
  }

  Future<void> _shutdown() async {
    await _subscription?.cancel();
    await _eventQueue;

    // Release any buttons still held when the driver is removed.
    for (final entry in _pressed.entries.toList()) {
      if (!entry.value) continue;

      final binding = _bindings[entry.key];
      if (binding == null) continue;

      try {
        await binding.buttonInput.release();
        _pressed[entry.key] = false;
      } catch (error) {
        debugPrint(
          '[GpioInputDriver] Could not release '
          '${binding.buttonInput.buttonCode.name}: $error',
        );
      }
    }
  }
}