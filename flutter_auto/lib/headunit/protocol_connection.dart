import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'message_assembler.dart';
import 'protocol_frame.dart';
import 'protocol_message.dart';

class ProtocolConnection {
  static final Logger _log = Logger('ProtocolConnection');
  ProtocolConnection(Socket socket) : _socket = socket {
    _subscription = _socket.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  final Socket _socket;

  final StreamController<ProtocolFrame> _frameController =
      StreamController<ProtocolFrame>();

  final Completer<void> _doneCompleter = Completer<void>();

  late final StreamSubscription<List<int>> _subscription;

  late final Stream<ProtocolMessage> _messages = const MessageAssembler().bind(
    _frameController.stream,
  );

  Uint8List _buffer = Uint8List(0);
  bool _isClosed = false;
  Future<void>? _closeFuture;

  Stream<ProtocolFrame> get frames => _frameController.stream;

  /// Complete protocol messages assembled from frames.
  ///
  /// This is a single-subscription stream. Listen only once per connection.
  Stream<ProtocolMessage> get messages => _messages;

  Future<void> get done => _doneCompleter.future;

  bool get isClosed => _isClosed;

  static const int _baseHeaderSize = 4;
  static const int _firstHeaderSize = 8;

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

      final ProtocolFrame frame = ProtocolFrame.decode(
        frameBytes,
        messageType: MessageType.control,
      );
      _frameController.add(frame);
      offset += frameLength;
    }

    if (offset > 0) {
      _buffer = Uint8List.fromList(_buffer.sublist(offset));
    }
  }

  Future<void> send(ProtocolFrame frame) async {
    if (_isClosed) {
      throw StateError('Cannot send data on a closed connection.');
    }

    final Uint8List encoded = frame.encode();

    _log.fine('AA TX (${encoded.length} bytes): ${_formatHex(encoded)}');

    _socket.add(encoded);
    await _socket.flush();
  }

  void _onError(Object error, StackTrace stackTrace) {
    _fail(error, stackTrace);
  }

  void _onDone() {
    _log.info('AA TCP: remote socket closed');
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

    _socket.destroy();
    _finish();
  }

  Future<void> close() {
    final Future<void>? existingClose = _closeFuture;

    if (existingClose != null) {
      return existingClose;
    }

    _closeFuture = _closeInternal();
    return _closeFuture!;
  }

  Future<void> _closeInternal() async {
    if (!_isClosed) {
      await _subscription.cancel();

      try {
        await _socket.close();
      } finally {
        _finish();
      }
    }
  }

  void _finish() {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _buffer = Uint8List(0);

    if (!_frameController.isClosed) {
      _frameController.close();
    }

    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }
}
