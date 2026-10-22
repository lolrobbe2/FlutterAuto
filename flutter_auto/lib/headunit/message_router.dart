
import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'protocol_connection.dart';
import 'protocol_message.dart';

/// Decrypts one encrypted frame payload.
typedef ApplicationDecryptor =
    Future<Uint8List> Function(Uint8List encryptedPayload);

/// Routes assembled protocol messages to independent listeners.
///
/// Frame decryption and message assembly happen upstream in
/// ProtocolConnection/MessageAssembler. This class does not decrypt.
class MessageRouter {
  MessageRouter(ProtocolConnection connection)
      : _connection = connection {
    _subscription = _connection.messages.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  static final Logger _log = Logger('MessageRouter');

  final ProtocolConnection _connection;

  final StreamController<ProtocolMessage> _controller =
      StreamController<ProtocolMessage>.broadcast();

  late final StreamSubscription<ProtocolMessage> _subscription;

  bool _isClosed = false;
  Future<void>? _closeFuture;

  // Preserve message order during asynchronous downstream processing.
  Future<void> _processing = Future<void>.value();

  Stream<ProtocolMessage> get messages => _controller.stream;

  bool get isClosed => _isClosed;

  /// Configures decryption upstream, before fragmented-message assembly.
  void setApplicationDecryptor(ApplicationDecryptor? decryptor) {
    if (_isClosed) {
      throw StateError('Cannot configure a closed MessageRouter.');
    }

    _connection.setFramePayloadDecryptor(decryptor);
  }

  /// Returns messages matching a channel and message ID.
  ///
  /// The message ID is the first two payload bytes, big-endian.
  Stream<ProtocolMessage> forMessageId(
    int messageId, {
    int? channel,
  }) {
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

      return ByteData.sublistView(message.payload)
              .getUint16(0, Endian.big) ==
          messageId;
    });
  }

  void _onMessage(ProtocolMessage message) {
    if (_isClosed) return;

    _processing = _processing
        .then((_) async {
          if (!_isClosed) {
            await _processMessage(message);
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          _log.severe(
            'Error while routing an incoming message.',
            error,
            stackTrace,
          );

          if (!_isClosed) {
            _controller.addError(error, stackTrace);
          }
        });
  }

  Future<void> _processMessage(ProtocolMessage message) async {
    if (_isClosed) return;

    final String hex = _formatHex(message.payload);

    _log.fine(
      'Router RX: channel=${message.channel}, '
      'type=${message.messageType}, '
      'encryption=${message.encryptionType}, '
      'length=${message.payload.length}, '
      'payload=[$hex]',
    );

    // The payload is already assembled. Do not decrypt it here:
    // doing so would process the TLS record a second time.
    _controller.add(message);
  }

  String _formatHex(List<int> bytes, {int maxBytes = 32}) {
    final String hex = bytes
        .take(maxBytes)
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');

    if (bytes.length > maxBytes) {
      return '$hex ... (${bytes.length} bytes total)';
    }

    return hex;
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (_isClosed) return;

    _log.severe('Protocol connection stream error.', error, stackTrace);
    _controller.addError(error, stackTrace);
  }

  void _onDone() {
    unawaited(close());
  }

  Future<void> close() {
    final existingClose = _closeFuture;
    if (existingClose != null) {
      return existingClose;
    }

    _isClosed = true;
    _closeFuture = _closeInternal();
    return _closeFuture!;
  }

  Future<void> _closeInternal() async {
    await _subscription.cancel();
    await _processing;
    await _controller.close();
  }
}
