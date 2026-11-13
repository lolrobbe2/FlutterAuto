import 'dart:async';
import 'dart:typed_data';

import '_media_socket.dart';
import '_media_wire.dart';
import '_video_frame_queue.dart';
import 'encoded_video_frame.dart';
import 'media_stream_configuration.dart';
import 'media_transport_exception.dart';

part 'media_frame_subscription.dart';

/// Host-side receiver for one external application's encoded video stream.
class MediaStreamConnection {
  final MediaSocketChannel _channel;
  final VideoFrameQueue _frameQueue;
  final VideoStreamConfiguration configuration;
  final int maxAccessUnitBytes;
  final void Function(MediaStreamConnection connection) _onClosed;

  bool _closed = false;
  bool _keyFrameRequestSent = false;
  int _lastSequence = -1;
  int _lastPresentationTime = -1;
  Future<void>? _readLoop;
  MediaFrameSubscription? _frameSubscription;

  MediaStreamConnection.fromAuthenticatedChannel({
    required this._channel,
    required this.configuration,
    required this.maxAccessUnitBytes,
    required int maxQueuedFrames,
    required this._onClosed,
  }) : _frameQueue = VideoFrameQueue(capacity: maxQueuedFrames) {
    _frameQueue.keyFrameRequests.listen((_) {
      _sendKeyFrameRequest();
    });
  }

  bool get isClosed => _closed;
  int get droppedFrames => _frameQueue.droppedFrames;

  /// Waits for the next decodable access unit. Returns null on disconnect.
  ///
  /// Prefer [createFrameSubscription] when the consumer has a shorter
  /// lifecycle than this connection (for example, a Flutter surface widget).
  Future<EncodedVideoFrame?> nextFrame() => _frameQueue.nextFrame();

  /// Creates the single cancellable frame reader for this connection.
  ///
  /// A connection represents one video stream and therefore has one consumer.
  /// The subscription can be cancelled without closing the connection.
  MediaFrameSubscription createFrameSubscription() {
    final MediaFrameSubscription? existing = _frameSubscription;
    if (existing != null && !existing.isCancelled) {
      throw StateError('A frame subscription is already active.');
    }

    late final MediaFrameSubscription subscription;
    subscription = MediaFrameSubscription._(
      queue: _frameQueue,
      onCancel: (MediaFrameSubscription cancelled) {
        if (identical(_frameSubscription, cancelled)) {
          _frameSubscription = null;
        }
      },
    );
    _frameSubscription = subscription;
    return subscription;
  }

  void start() {
    // The SDK requires an IDR as its first frame. A keyframe request is sent
    // if the first received access unit is not a keyframe.
    _readLoop = _readFrames();
  }

  Future<void> _readFrames() async {
    try {
      while (!_closed) {
        final Uint8List? record = await _channel.readRecord();
        if (record == null) {
          break;
        }
        final EncodedVideoFrame frame = decodeVideoFrame(record);
        if (frame.data.length > maxAccessUnitBytes) {
          throw MediaTransportException(
            'Video access unit exceeds the $maxAccessUnitBytes byte limit.',
          );
        }
        if (frame.sequenceNumber <= _lastSequence ||
            frame.presentationTimeMicros < _lastPresentationTime) {
          throw const MediaTransportException(
            'Video frame sequence or timestamp moved backwards.',
          );
        }
        _lastSequence = frame.sequenceNumber;
        _lastPresentationTime = frame.presentationTimeMicros;
        if (frame.isKeyFrame) {
          _keyFrameRequestSent = false;
        }
        _frameQueue.add(frame);
      }
    } catch (_) {
      // Closure is surfaced through nextFrame() returning null.
    } finally {
      await _closeInternal();
    }
  }

  void _sendKeyFrameRequest() {
    if (_closed || _keyFrameRequestSent) {
      return;
    }
    _keyFrameRequestSent = true;
    unawaited(
      _channel
          .writeRecord(<Uint8List>[requestKeyFrameRecord], payloadLength: 1)
          .catchError((Object _) {
            // Connection teardown races are handled by _readFrames.
          }),
    );
  }

  Future<void> _closeInternal() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _frameQueue.close();
    await _channel.close();
    _onClosed(this);
  }

  Future<void> close() async {
    await _closeInternal();
    final Future<void>? readLoop = _readLoop;
    if (readLoop != null) {
      await readLoop;
    }
  }
}
