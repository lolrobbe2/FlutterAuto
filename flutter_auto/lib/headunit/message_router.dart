import 'dart:async';
import 'dart:typed_data';

import 'protocol_connection.dart';
import 'protocol_message.dart';

/// Distributes complete protocol messages to multiple independent listeners.
///
/// Create one router per ProtocolConnection because the connection's
/// messages stream is single-subscription.
class MessageRouter {
  MessageRouter(ProtocolConnection connection) {
    _subscription = connection.messages.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  final StreamController<ProtocolMessage> _controller =
      StreamController<ProtocolMessage>.broadcast();

  late final StreamSubscription<ProtocolMessage> _subscription;

  bool _isClosed = false;
  Future<void>? _closeFuture;

  Stream<ProtocolMessage> get messages => _controller.stream;

  bool get isClosed => _isClosed;

  /// Returns messages matching a channel and message ID.
  ///
  /// The message ID is the first two payload bytes, big-endian.
  Stream<ProtocolMessage> forMessageId(int messageId, {int? channel}) {
    if (messageId < 0 || messageId > 0xFFFF) {
      throw ArgumentError.value(
        messageId,
        'messageId',
        'Must fit in an unsigned 16-bit integer.',
      );
    }

    if (channel != null && (channel < 0 || channel > 0xFF)) {
      throw ArgumentError.value(
        channel,
        'channel',
        'Must fit in an unsigned 8-bit integer.',
      );
    }

    return messages.where((ProtocolMessage message) {
      if (channel != null && message.channel != channel) {
        return false;
      }

      if (message.payload.length < 2) {
        return false;
      }

      final ByteData data = ByteData.sublistView(message.payload);
      return data.getUint16(0, Endian.big) == messageId;
    });
  }

  void _onMessage(ProtocolMessage message) {
    if (!_isClosed) {
      _controller.add(message);
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (!_isClosed) {
      _controller.addError(error, stackTrace);
    }
  }

  void _onDone() {
    unawaited(close());
  }

  Future<void> close() {
    final Future<void>? existingClose = _closeFuture;
    if (existingClose != null) {
      return existingClose;
    }

    _isClosed = true;
    _closeFuture = _closeInternal();
    return _closeFuture!;
  }

  Future<void> _closeInternal() async {
    unawaited(_subscription.cancel());
    await _controller.close();
  }
}
