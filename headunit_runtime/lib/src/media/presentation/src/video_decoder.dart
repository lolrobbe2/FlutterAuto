import 'package:flutter/widgets.dart';
import 'package:headunit_shared/headunit_shared_io.dart'
    show EncodedVideoFrame, VideoStreamConfiguration;

/// Decodes one remote application's compressed video stream into a Flutter
/// widget.
///
/// Implementations must keep their input buffering bounded. The decoder owns
/// its rendering resources but does not own the media connection.
abstract interface class VideoDecoder {
  /// The visual representation of the decoded video.
  Widget buildView();

  /// Feeds one Annex-B access unit to the decoder.
  ///
  /// Implementations must apply backpressure rather than accumulating an
  /// unbounded queue of encoded frames.
  Future<void> decode(EncodedVideoFrame frame);

  /// Releases the decoder and its rendering resources.
  ///
  /// Disposal must be idempotent and wait for any in-flight [decode] operation.
  Future<void> dispose();
}

/// Optional startup phase for decoders whose player must wait until
/// [VideoDecoder.buildView] has been mounted in the widget tree.
///
/// Keeping this separate preserves compatibility with decoder implementations
/// that can accept frames immediately after construction.
abstract interface class StartableVideoDecoder extends VideoDecoder {
  /// Starts decoding after the output widget has been mounted.
  ///
  /// Implementations should make this operation idempotent.
  Future<void> start();
}

typedef VideoDecoderFactory = Future<VideoDecoder> Function(
  VideoStreamConfiguration configuration,
);
