import 'dart:async';
import 'dart:collection';

import 'encoded_video_frame.dart';

/// Bounded latest-frame queue that never hands dependent delta frames to a
/// decoder after the queue has overflowed. It waits for the next keyframe.
class VideoFrameQueue {
  final int capacity;
  final Queue<EncodedVideoFrame> _frames = Queue<EncodedVideoFrame>();
  final Queue<_FrameWaiter> _waiters = Queue<_FrameWaiter>();
  final StreamController<void> _keyFrameRequests =
      StreamController<void>.broadcast(sync: true);

  bool _closed = false;
  bool _awaitingKeyFrame = true;
  int _droppedFrames = 0;

  VideoFrameQueue({this.capacity = 2}) {
    if (capacity < 1 || capacity > 8) {
      throw ArgumentError.value(capacity, 'capacity');
    }
  }

  int get droppedFrames => _droppedFrames;
  bool get isClosed => _closed;
  Stream<void> get keyFrameRequests => _keyFrameRequests.stream;

  /// Returns true when the producer should be asked for a new keyframe.
  bool add(EncodedVideoFrame frame) {
    if (_closed) {
      return false;
    }

    if (_awaitingKeyFrame && !frame.isKeyFrame) {
      _droppedFrames++;
      _requestKeyFrame();
      return true;
    }

    if (_frames.length >= capacity) {
      _droppedFrames += _frames.length;
      _frames.clear();
      _awaitingKeyFrame = true;
      if (!frame.isKeyFrame) {
        _droppedFrames++;
        _requestKeyFrame();
        return true;
      }
      // A keyframe can recover the queue immediately without another request.
    }

    _awaitingKeyFrame = false;
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().completer.complete(frame);
    } else {
      _frames.addLast(frame);
    }
    return false;
  }

  Future<EncodedVideoFrame?> nextFrame({Object? owner}) {
    if (_frames.isNotEmpty) {
      return Future<EncodedVideoFrame?>.value(_frames.removeFirst());
    }
    if (_closed) {
      return Future<EncodedVideoFrame?>.value(null);
    }
    final Completer<EncodedVideoFrame?> completer =
        Completer<EncodedVideoFrame?>();
    _waiters.addLast(_FrameWaiter(owner: owner, completer: completer));
    return completer.future;
  }

  /// Cancels a pending read and forces the next reader to start at a keyframe.
  void cancelReader(Object owner) {
    if (_waiters.isNotEmpty) {
      final Queue<_FrameWaiter> retained = Queue<_FrameWaiter>();
      while (_waiters.isNotEmpty) {
        final _FrameWaiter waiter = _waiters.removeFirst();
        if (identical(waiter.owner, owner)) {
          if (!waiter.completer.isCompleted) {
            waiter.completer.complete(null);
          }
        } else {
          retained.addLast(waiter);
        }
      }
      _waiters.addAll(retained);
    }

    // A new decoder cannot continue from the old decoder's reference frames.
    _droppedFrames += _frames.length;
    _frames.clear();
    _awaitingKeyFrame = true;
    _requestKeyFrame();
  }

  void _requestKeyFrame() {
    if (!_keyFrameRequests.isClosed) {
      _keyFrameRequests.add(null);
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _frames.clear();
    while (_waiters.isNotEmpty) {
      final _FrameWaiter waiter = _waiters.removeFirst();
      if (!waiter.completer.isCompleted) {
        waiter.completer.complete(null);
      }
    }
    await _keyFrameRequests.close();
  }
}

class _FrameWaiter {
  final Object? owner;
  final Completer<EncodedVideoFrame?> completer;

  const _FrameWaiter({required this.owner, required this.completer});
}
