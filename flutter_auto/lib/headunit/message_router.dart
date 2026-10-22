import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'protocol_connection.dart';
import 'protocol_message.dart';

/// Decrypts a complete incoming application-data payload.
typedef ApplicationDecryptor =
    Future<Uint8List> Function(Uint8List encryptedPayload);

/// Routes complete protocol messages to independent listeners.
///
/// Incoming encrypted messages are decrypted sequentially before being
/// broadcast. SSL_HANDSHAKE messages are passed through unchanged.
class MessageRouter {
  MessageRouter(ProtocolConnection connection) {
    _subscription = connection.messages.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  static final Logger _log = Logger('MessageRouter');

  static const int sslHandshakeMessageId = 0x0003;

  final StreamController<ProtocolMessage> _controller =
      StreamController<ProtocolMessage>.broadcast();

  late final StreamSubscription<ProtocolMessage> _subscription;

  ApplicationDecryptor? _applicationDecryptor;

  bool _isClosed = false;
  Future<void>? _closeFuture;

  // Keep incoming messages in order, even when decryption is asynchronous.
  Future<void> _processing = Future<void>.value();

  Stream<ProtocolMessage> get messages => _controller.stream;

  bool get isClosed => _isClosed;

  void setApplicationDecryptor(ApplicationDecryptor? decryptor) {
    if (_isClosed) {
      throw StateError('Cannot configure a closed MessageRouter.');
    }
    _applicationDecryptor = decryptor;
  }

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

      return ByteData.sublistView(message.payload).getUint16(0, Endian.big) ==
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
            'Unhandled error while processing an incoming message.',
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

    // TLS handshake records must bypass application-data decryption.
    final bool isSslHandshake =
        message.channel == 0 &&
        message.payload.length >= 2 &&
        ByteData.sublistView(message.payload).getUint16(0, Endian.big) ==
            sslHandshakeMessageId;

    if (isSslHandshake) {
      _log.fine('Passing SSL_HANDSHAKE message through unchanged.');
      _controller.add(message);
      return;
    }

    // Pass plaintext messages through unchanged.
    if (message.encryptionType.name != 'encrypted') {
      _log.fine('Passing unencrypted message through unchanged.');
      _controller.add(message);
      return;
    }

    final ApplicationDecryptor? decryptor = _applicationDecryptor;

    if (decryptor == null) {
      final error = StateError(
        'Received an encrypted message before an application '
        'decryptor was installed.',
      );

      _log.severe('Cannot process encrypted message.', error);
      _controller.addError(error, StackTrace.current);
      return;
    }

    try {
      _log.fine(
        'Decrypting ${message.payload.length} bytes '
        'on channel ${message.channel}.',
      );

      final Uint8List decryptedPayload = await decryptor(
        Uint8List.fromList(message.payload),
      );

      if (_isClosed) return;

      _log.fine(
        'Decryption complete: ${decryptedPayload.length} bytes, '
        'payload=[${_formatHex(decryptedPayload)}]',
      );

      if (decryptedPayload.length >= 2) {
        final int messageId = ByteData.sublistView(
          decryptedPayload,
        ).getUint16(0, Endian.big);

        _log.fine(
          'Decrypted message ID: 0x'
          '${messageId.toRadixString(16).padLeft(4, '0')}.',
        );
      }

      _controller.add(
        ProtocolMessage(
          channel: message.channel,
          messageType: message.messageType,
          encryptionType: message.encryptionType,
          payload: decryptedPayload,
        ),
      );
    } catch (error, stackTrace) {
      _log.severe(
        'Failed to decrypt incoming message on channel '
        '${message.channel}.',
        error,
        stackTrace,
      );

      if (!_isClosed) {
        _controller.addError(error, stackTrace);
      }
    }
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
    final Future<void>? existingClose = _closeFuture;
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
