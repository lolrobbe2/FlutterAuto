import 'package:fixnum/fixnum.dart';

import '../../generated/oaa/input/ButtonCodeEnum.pbenum.dart';
import '../../generated/oaa/input/ButtonEventData.pb.dart';
import '../../generated/oaa/input/ButtonEventsData.pb.dart';
import '../../generated/oaa/input/InputEventIndicationMessage.pb.dart';
import 'input_base.dart';
import '../protocol_frame.dart';
import '../protocol_message.dart';

class InputButton extends InputBase {
  InputButton(this.buttonCode) : super('InputButton') {
    if (buttonCode == ButtonCode_Enum.NONE) {
      throw ArgumentError.value(
        buttonCode,
        'buttonCode',
        'NONE cannot be used as a button.',
      );
    }
  }

  static const int inputEventIndicationId = 0x8001;

  final ButtonCode_Enum buttonCode;
  final Stopwatch _clock = Stopwatch()..start();

  bool _isPressed = false;

  bool get isPressed => _isPressed;

  /// Sends a button-down event.
  Future<void> press({
    int metaState = 0,
    bool longPress = false,
  }) async {
    if (_isPressed) {
      throw StateError('${buttonCode.name} is already pressed.');
    }

    _isPressed = true;

    try {
      await _sendButtonEvent(
        isPressed: true,
        metaState: metaState,
        longPress: longPress,
      );
    } catch (_) {
      _isPressed = false;
      rethrow;
    }
  }

  /// Sends a button-up event.
  Future<void> release({
    int metaState = 0,
    bool longPress = false,
  }) async {
    if (!_isPressed) {
      throw StateError('${buttonCode.name} is not pressed.');
    }

    await _sendButtonEvent(
      isPressed: false,
      metaState: metaState,
      longPress: longPress,
    );

    _isPressed = false;
  }

  /// Sends a complete press and release.
  Future<void> tap({
    int metaState = 0,
    Duration holdDuration = const Duration(milliseconds: 50),
  }) async {
    if (holdDuration.isNegative) {
      throw ArgumentError.value(
        holdDuration,
        'holdDuration',
        'Must not be negative.',
      );
    }

    await press(metaState: metaState);

    try {
      if (holdDuration > Duration.zero) {
        await Future<void>.delayed(holdDuration);
      }
    } finally {
      if (_isPressed) {
        await release(metaState: metaState);
      }
    }
  }

  Future<void> _sendButtonEvent({
    required bool isPressed,
    required int metaState,
    required bool longPress,
  }) async {
    final event = ButtonEvent()
      ..keycode = buttonCode.value
      ..isPressed = isPressed
      ..metaState = metaState
      ..longPress = longPress;

    final events = ButtonEvents()..buttonEvents.add(event);

    final indication = InputEventIndication()
      ..timestamp = Int64(_clock.elapsedMicroseconds)
      ..buttonEvent = events;

    log.fine(
      'TX BUTTON: ${buttonCode.name} '
      '(keycode=${buttonCode.value}), '
      'pressed=$isPressed, '
      'metaState=$metaState, '
      'longPress=$longPress',
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
    final id = messageIdOf(message);
    final body = bodyOf(message);

    log.fine(
      'InputButton received message '
      '0x${id.toRadixString(16).padLeft(4, '0')}, '
      'bodyBytes=${body.length}.',
    );
  }

  @override
  Future<void> dispose() async {
    _isPressed = false;
    await super.dispose();
  }
}