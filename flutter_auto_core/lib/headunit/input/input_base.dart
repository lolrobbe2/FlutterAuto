import 'dart:typed_data';

import '../protocol_frame.dart';
import '../protocol_message.dart';
import 'package:logging/logging.dart';

typedef InputSendMessage =
    Future<void> Function({
      required int messageId,
      required Uint8List body,
      required EncryptionType encryptionType,
      required MessageType messageType,
      required FrameType frameType,
    });

abstract class InputBase {
  final Logger log;
  InputBase(String loggerName) : log = Logger(loggerName);
  // Functions supplied by the owning ChannelService.
  late final int Function(ProtocolMessage message) messageIdOf;
  late final Uint8List Function(ProtocolMessage message) bodyOf;
  late final InputSendMessage sendMessage;

  bool _bound = false;

  void bindChannel({
    required int Function(ProtocolMessage message) messageIdOf,
    required Uint8List Function(ProtocolMessage message) bodyOf,
    required InputSendMessage sendMessage,
  }) {
    if (_bound) {
      throw StateError('InputBase is already bound to a channel.');
    }

    this.messageIdOf = messageIdOf;
    this.bodyOf = bodyOf;
    this.sendMessage = sendMessage;

    _bound = true;
  }

  /// Override this in inputs that handle incoming messages.
  Future<void> handleMessage(ProtocolMessage message) async {}

  Future<void> dispose() async {}
}
