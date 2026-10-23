import 'package:fixnum/fixnum.dart';

import 'package:flutter_auto/generated/oaa/input/InputEventIndicationMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/input/TouchActionEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/input/TouchEventData.pb.dart';
import 'package:flutter_auto/generated/oaa/input/TouchLocationData.pb.dart';
import 'package:flutter_auto/generated/oaa/input/TouchScreenConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/video/DisplayTypeEnum.pbenum.dart';
import 'package:flutter_auto/headunit/input/input_base.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';
import 'package:flutter_auto/headunit/protocol_message.dart';

class TouchInput extends InputBase {
  TouchInput({
    this.width = 800,
    this.height = 480,
    this.displayType = DisplayType_Enum.MAIN,
  })  : assert(width > 0),
        assert(height > 0),super('TouchInput');

  static const int inputEventIndicationId = 0x8001;

  final int width;
  final int height;
  final DisplayType_Enum displayType;

  final Stopwatch _clock = Stopwatch()..start();

  // Dart's default Map preserves insertion order.
  // That order determines actionIndex for pointer events.
  final Map<int, _TouchPoint> _activePointers = {};

  /// Creates the touchscreen configuration advertised to Android Auto.
  TouchScreenConfig buildConfig() {
    return TouchScreenConfig(
      width: width,
      height: height,
      displayType: displayType,
    );
  }

  /// First finger touches the screen: PRESS.
  Future<void> press({
    required int x,
    required int y,
    int pointerId = 0,
  }) async {
    if (_activePointers.isNotEmpty) {
      throw StateError(
        'A pointer is already active. Use pointerDown() for another finger.',
      );
    }

    _activePointers[pointerId] = _TouchPoint(
      x: _clampX(x),
      y: _clampY(y),
    );

    try {
      await _sendTouchEvent(TouchAction_Enum.PRESS);
    } catch (_) {
      _activePointers.remove(pointerId);
      rethrow;
    }
  }

  /// Moves an active finger: DRAG.
  ///
  /// The event includes every currently active pointer.
  Future<void> drag({
    required int x,
    required int y,
    int pointerId = 0,
  }) async {
    final point = _activePointers[pointerId];

    if (point == null) {
      throw StateError('Cannot drag pointer $pointerId: it is not active.');
    }

    point.x = _clampX(x);
    point.y = _clampY(y);

    await _sendTouchEvent(TouchAction_Enum.DRAG);
  }

  /// Releases the only active finger: RELEASE.
  Future<void> release({int pointerId = 0}) async {
    if (_activePointers.length != 1 ||
        !_activePointers.containsKey(pointerId)) {
      throw StateError(
        'RELEASE requires the only active pointer. '
        'Use pointerUp() when multiple pointers are active.',
      );
    }

    // The released pointer must still be included in the event.
    await _sendTouchEvent(TouchAction_Enum.RELEASE);

    _activePointers.remove(pointerId);
  }

  /// Adds another finger while at least one pointer is already active.
  Future<void> pointerDown({
    required int x,
    required int y,
    required int pointerId,
  }) async {
    if (_activePointers.isEmpty) {
      throw StateError('Call press() for the first pointer.');
    }

    if (_activePointers.containsKey(pointerId)) {
      throw StateError('Pointer $pointerId is already active.');
    }

    _activePointers[pointerId] = _TouchPoint(
      x: _clampX(x),
      y: _clampY(y),
    );

    try {
      final actionIndex = _pointerIndex(pointerId);

      await _sendTouchEvent(
        TouchAction_Enum.POINTER_DOWN,
        actionIndex: actionIndex,
      );
    } catch (_) {
      _activePointers.remove(pointerId);
      rethrow;
    }
  }

  /// Lifts one finger while other fingers remain active.
  Future<void> pointerUp({required int pointerId}) async {
    if (_activePointers.length < 2) {
      throw StateError(
        'POINTER_UP requires at least two active pointers. '
        'Use release() for the last pointer.',
      );
    }

    if (!_activePointers.containsKey(pointerId)) {
      throw StateError('Pointer $pointerId is not active.');
    }

    // Keep the lifted pointer in the message and calculate its index
    // before removing it.
    final actionIndex = _pointerIndex(pointerId);

    await _sendTouchEvent(
      TouchAction_Enum.POINTER_UP,
      actionIndex: actionIndex,
    );

    _activePointers.remove(pointerId);
  }

  int _pointerIndex(int pointerId) {
    return _activePointers.keys.toList().indexOf(pointerId);
  }

  int _clampX(int x) => x.clamp(0, width - 1);

  int _clampY(int y) => y.clamp(0, height - 1);

  /// Sends an InputEventIndication containing the complete touch state.
  Future<void> _sendTouchEvent(
    TouchAction_Enum action, {
    int actionIndex = 0,
  }) async {
    if (_activePointers.isEmpty) {
      throw StateError('Cannot send a touch event without active pointers.');
    }

    final touchEvent = TouchEvent()
      ..touchLocation.addAll(
        _activePointers.entries.map((entry) {
          return TouchLocation()
            ..pointerId = entry.key
            ..x = entry.value.x
            ..y = entry.value.y;
        }),
      )
      ..actionIndex = actionIndex
      ..touchAction = action;

    final indication = InputEventIndication()
      ..timestamp = Int64(_clock.elapsedMicroseconds)
      ..touchEvent = touchEvent;

    log.fine(
      'TX TOUCH: action=${action.name}, '
      'actionIndex=$actionIndex, '
      'pointers=${_activePointers.length}.',
    );

    await sendMessage(
      messageId: inputEventIndicationId,
      body: indication.writeToBuffer(),
      encryptionType: EncryptionType.encrypted,
      messageType: MessageType.specific,
      frameType: FrameType.bulk,
    );
  }

  @override
  Future<void> handleMessage(ProtocolMessage message) async {
    // TouchInput currently sends touch events only.
    // Use the injected helpers if incoming touch-related messages
    // need handling in the future.
    final id = messageIdOf(message);
    final body = bodyOf(message);

    log.fine(
      'TouchInput received message '
      '0x${id.toRadixString(16).padLeft(4, '0')}, '
      'bodyBytes=${body.length}.',
    );
  }

  @override
  Future<void> dispose() async {
    _activePointers.clear();
    await super.dispose();
  }
}

class _TouchPoint {
  _TouchPoint({
    required this.x,
    required this.y,
  });

  int x;
  int y;
}