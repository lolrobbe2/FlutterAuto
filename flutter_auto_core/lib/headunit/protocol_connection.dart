import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_auto_core/headunit/transport/protocol_transport.dart';
import 'package:flutter_auto_core/headunit/transport/socket_protocol_transport.dart';
import 'package:logging/logging.dart';

import 'message_assembler.dart';
import 'protocol_frame.dart';
import 'protocol_message.dart';

class ProtocolConnection {
  /// Backwards-compatible constructor for existing TCP callers.
  ProtocolConnection(Socket socket)
      : this.fromTransport(SocketProtocolTransport(socket));

  /// Creates a connection over any supported byte transport.
  ProtocolConnection.fromTransport(ProtocolTransport transport)
      : _transport = transport {
    _subscription = _transport.input.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  static final Logger _log = Logger('ProtocolConnection');

  final ProtocolTransport _transport;

  final StreamController<ProtocolFrame> _frameController =
      StreamController<ProtocolFrame>();

  final Completer<void> _doneCompleter = Completer<void>();

  late final StreamSubscription<List<int>> _subscription;

  FramePayloadDecryptor? _framePayloadDecryptor;

  late final Stream<ProtocolMessage> _messages =
      const MessageAssembler().bind(
    _frameController.stream,
    decryptEncryptedPayload: (Uint8List payload) async {
      final decryptor = _framePayloadDecryptor;

      if (decryptor == null) {
        throw StateError(
          'Encrypted frame received before TLS decryption was configured.',
        );
      }

      return decryptor(payload);
    },
  );

  Uint8List _buffer = Uint8List(0);
  bool _isClosed = false;
  bool _isClosing = false;

  Future<void>? _closeFuture;
  Future<void> _sendQueue = Future<void>.value();

  Stream<ProtocolFrame> get frames => _frameController.stream;

  /// Complete protocol messages assembled from frames.
  ///
  /// This is a single-subscription stream. Listen only once per connection.
  Stream<ProtocolMessage> get messages => _messages;

  Future<void> get done => _doneCompleter.future;

  bool get isClosed => _isClosed;

  static const int _baseHeaderSize = 4;
  static const int _firstHeaderSize = 8;

  void setFramePayloadDecryptor(FramePayloadDecryptor? decryptor) {
    if (_isClosed) {
      throw StateError('Cannot configure a closed protocol connection.');
    }

    _framePayloadDecryptor = decryptor;
  }

  void _onData(List<int> data) {
    if (_isClosed || data.isEmpty) {
      return;
    }

    _log.fine('AA RX: ${_formatHex(data)}');
    _appendData(data);

    try {
      _processBuffer();
    } on FormatException catch (error, stackTrace) {
      _fail(error, stackTrace);
    } on ArgumentError catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  String _formatHex(List<int> bytes) =>
      bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  void _appendData(List<int> data) {
    final Uint8List combined = Uint8List(_buffer.length + data.length);

    combined.setRange(0, _buffer.length, _buffer);
    combined.setRange(_buffer.length, combined.length, data);

    _buffer = combined;
  }

  void _processBuffer() {
    int offset = 0;

    while (_buffer.length - offset >= _baseHeaderSize) {
      final int flags = _buffer[offset + 1];
      final int rawFrameType = flags & 0x03;

      final int headerSize = rawFrameType == FrameType.first.index
          ? _firstHeaderSize
          : _baseHeaderSize;

      if (_buffer.length - offset < headerSize) {
        break;
      }

      final int payloadLength =
          (_buffer[offset + 2] << 8) | _buffer[offset + 3];

      final int frameLength = headerSize + payloadLength;

      if (_buffer.length - offset < frameLength) {
        break;
      }

      final Uint8List frameBytes = Uint8List.fromList(
        _buffer.sublist(offset, offset + frameLength),
      );

      final ProtocolFrame frame = ProtocolFrame.decode(frameBytes);
      _frameController.add(frame);

      offset += frameLength;
    }

    if (offset > 0) {
      _buffer = Uint8List.fromList(_buffer.sublist(offset));
    }
  }

  Future<void> send(ProtocolFrame frame) {
    if (_isClosed || _isClosing) {
      return Future<void>.error(
        StateError('Cannot send data on a closed connection.'),
      );
    }

    // Encode before queuing so each operation owns its immutable bytes.
    final Uint8List encoded = frame.encode();

    _log.fine('AA TX (${encoded.length} bytes): ${_formatHex(encoded)}');

    // Queue each transport write behind the previous one.
    final Future<void> operation = _sendQueue.then<void>((_) async {
      if (_isClosed) {
        throw StateError('Cannot send data on a closed connection.');
      }

      await _transport.write(encoded);
    });

    // Keep the queue usable if an individual operation fails.
    // The original operation still propagates its error to its caller.
    _sendQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _log.warning('Queued transport write failed.', error, stackTrace);
      },
    );

    return operation;
  }

  void _onError(Object error, StackTrace stackTrace) {
    _fail(error, stackTrace);
  }

  void _onDone() {
    _log.info('AA transport: incoming stream closed');
    _finish();
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_isClosed) {
      return;
    }

    _log.severe('Protocol connection failed', error, stackTrace);

    if (!_frameController.isClosed) {
      _frameController.addError(error, stackTrace);
    }

    unawaited(_abortTransportSafely());
    unawaited(_cancelSubscriptionSafely());

    _finish();
  }

  Future<void> _abortTransportSafely() async {
    try {
      await _transport.abort();
    } catch (error, stackTrace) {
      _log.warning('Failed to abort the transport.', error, stackTrace);
    }
  }

  Future<void> _cancelSubscriptionSafely() async {
    try {
      await _subscription.cancel();
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to cancel the transport subscription.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> close() {
    final existingClose = _closeFuture;

    if (existingClose != null) {
      return existingClose;
    }

    // Reject new writes immediately, while allowing already-queued writes
    // to finish before closing the transport.
    _isClosing = true;

    _closeFuture = _closeInternal();
    return _closeFuture!;
  }

  Future<void> _closeInternal() async {
    if (_isClosed) return;

    try {
      await _subscription.cancel();

      // Wait until all previously accepted writes have completed.
      await _sendQueue;

      await _transport.close();
    } finally {
      _finish();
    }
  }

  void _finish() {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _buffer = Uint8List(0);

    if (!_frameController.isClosed) {
      unawaited(_frameController.close());
    }

    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }
}