import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '_media_socket.dart';
import '_media_wire.dart';
import 'encoded_video_frame.dart';
import 'media_stream_configuration.dart';
import 'media_transport_exception.dart';

/// Application-side sender for one authenticated H.264/H.265 stream.
class MediaStreamClient {
  static const int defaultMaxAccessUnitBytes = 2 * 1024 * 1024;
  static const int defaultMaxBufferedWriteBytes = 4 * 1024 * 1024;

  final MediaSocketChannel _channel;
  final int maxAccessUnitBytes;
  final VideoStreamConfiguration configuration;
  final StreamController<void> _keyFrameRequests =
      StreamController<void>.broadcast(sync: true);

  bool _closed = false;
  bool _requiresKeyFrame = true;
  int _lastSequence = -1;
  int _lastPresentationTime = -1;
  bool _sendingFrame = false;
  Future<void>? _readLoop;

  MediaStreamClient._({
    required this._channel,
    required this.maxAccessUnitBytes,
    required this.configuration,
  }) {
    _readLoop = _readControlMessages();
  }

  static Future<MediaStreamClient> connect({
    required String host,
    required int port,
    required String token,
    Duration timeout = const Duration(seconds: 5),
    int maxAccessUnitBytes = defaultMaxAccessUnitBytes,
    int maxBufferedWriteBytes = defaultMaxBufferedWriteBytes,
  }) async {
    if (host != '127.0.0.1') {
      throw ArgumentError.value(
        host,
        'host',
        'Media transport is restricted to IPv4 loopback.',
      );
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port');
    }
    if (maxAccessUnitBytes < 1024 || maxAccessUnitBytes > 16 * 1024 * 1024) {
      throw ArgumentError.value(maxAccessUnitBytes, 'maxAccessUnitBytes');
    }
    if (maxBufferedWriteBytes < 1024 ||
        maxBufferedWriteBytes > 64 * 1024 * 1024) {
      throw ArgumentError.value(maxBufferedWriteBytes, 'maxBufferedWriteBytes');
    }

    final Socket socket = await Socket.connect(host, port, timeout: timeout);
    final MediaSocketChannel channel = MediaSocketChannel(
      socket,
      maxRecordBytes: maxAccessUnitBytes + videoFrameHeaderBytes,
      maxBufferedWriteBytes: maxBufferedWriteBytes,
    );

    try {
      final Uint8List hello = encodeHello(token);
      await channel.writeRecord(<Uint8List>[
        hello,
      ], payloadLength: hello.length);
      final Uint8List? configurationRecord = await channel.readRecord().timeout(
        timeout,
      );
      if (configurationRecord == null) {
        throw const MediaTransportException(
          'Media server closed before sending configuration.',
        );
      }
      final VideoStreamConfiguration configuration = decodeConfiguration(
        configurationRecord,
      );
      return MediaStreamClient._(
        channel: channel,
        maxAccessUnitBytes: maxAccessUnitBytes,
        configuration: configuration,
      );
    } catch (_) {
      await channel.close();
      rethrow;
    }
  }

  bool get isClosed => _closed;

  /// True until an IDR/keyframe has been sent after connection or a request.
  bool get requiresKeyFrame => _requiresKeyFrame;

  /// Subscribe to this stream and force the encoder to emit an IDR frame.
  Stream<void> get keyFrameRequests => _keyFrameRequests.stream;

  Future<void> sendFrame(EncodedVideoFrame frame) async {
    _ensureOpen();
    if (_sendingFrame) {
      throw StateError('Only one encoded frame may be sent at a time.');
    }
    _sendingFrame = true;
    try {
      await _sendFrameInternal(frame);
    } finally {
      _sendingFrame = false;
    }
  }

  Future<void> _sendFrameInternal(EncodedVideoFrame frame) async {
    _ensureOpen();
    if (frame.data.length > maxAccessUnitBytes) {
      throw MediaTransportException(
        'Access unit exceeds the $maxAccessUnitBytes byte limit.',
      );
    }
    if (frame.sequenceNumber <= _lastSequence) {
      throw ArgumentError.value(
        frame.sequenceNumber,
        'sequenceNumber',
        'Sequence numbers must increase.',
      );
    }
    if (frame.presentationTimeMicros < _lastPresentationTime) {
      throw ArgumentError.value(
        frame.presentationTimeMicros,
        'presentationTimeMicros',
        'Presentation timestamps must not move backwards.',
      );
    }
    if (_requiresKeyFrame && !frame.isKeyFrame) {
      throw StateError('The encoder must send a keyframe before delta frames.');
    }

    final Uint8List frameHeader = encodeVideoFrameHeader(frame);
    await _channel.writeRecord(<Uint8List>[
      frameHeader,
      frame.data,
    ], payloadLength: frameHeader.length + frame.data.length);
    _lastSequence = frame.sequenceNumber;
    _lastPresentationTime = frame.presentationTimeMicros;
    if (frame.isKeyFrame) {
      _requiresKeyFrame = false;
    }
  }

  Future<void> _readControlMessages() async {
    try {
      while (!_closed) {
        final Uint8List? record = await _channel.readRecord();
        if (record == null) {
          break;
        }
        if (!isRequestKeyFrameRecord(record)) {
          throw const MediaTransportException(
            'Unexpected media control record from host.',
          );
        }
        _requiresKeyFrame = true;
        if (!_keyFrameRequests.isClosed) {
          _keyFrameRequests.add(null);
        }
      }
    } catch (_) {
      // The owner observes closure through isClosed and send errors.
    } finally {
      await _closeInternal();
    }
  }

  void _ensureOpen() {
    if (_closed || _channel.isClosed) {
      throw StateError('Media stream client is closed.');
    }
  }

  Future<void> _closeInternal() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _channel.close();
    if (!_keyFrameRequests.isClosed) {
      await _keyFrameRequests.close();
    }
  }

  Future<void> close() async {
    await _closeInternal();
    final Future<void>? readLoop = _readLoop;
    if (readLoop != null) {
      await readLoop;
    }
  }
}
