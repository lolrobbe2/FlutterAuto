part of 'media_stream_connection.dart';

/// A cancellable, single-consumer view of a media connection's frame queue.
///
/// Cancelling completes a pending [nextFrame] call with null without closing
/// the underlying connection. It drops queued reference frames and requests a
/// fresh keyframe so a later decoder can safely resume.
class MediaFrameSubscription {
  final VideoFrameQueue _queue;
  final Object _owner = Object();
  final void Function(MediaFrameSubscription subscription) _onCancel;

  bool _cancelled = false;

  MediaFrameSubscription._({
    required this._queue,
    required this._onCancel,
  });

  bool get isCancelled => _cancelled;

  /// Returns the next frame, or null after cancellation or stream closure.
  Future<EncodedVideoFrame?> nextFrame() {
    if (_cancelled) {
      return Future<EncodedVideoFrame?>.value(null);
    }
    return _queue.nextFrame(owner: _owner);
  }

  /// Cancels this reader but leaves the media connection open.
  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _queue.cancelReader(_owner);
    _onCancel(this);
  }
}
