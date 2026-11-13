import 'package:headunit_shared/headunit_shared_io.dart';

/// Decodes one remote application's compressed video stream into a Flutter
/// texture.
///
/// Platform implementations should use the operating system's hardware video
/// decoder where available (MediaCodec on Android, Media Foundation on
/// Windows). The interface deliberately exposes encoded access units rather
/// than raw pixels so the Dart layer does not copy full-resolution RGBA frames.
abstract interface class VideoDecoder {
  /// Flutter texture identifier registered by the native decoder.
  int get textureId;

  /// Queues one Annex-B access unit for decoding.
  ///
  /// Implementations must keep their internal input queue bounded. When the
  /// decoder cannot keep up, they should discard dependent frames until the
  /// next keyframe rather than accumulating latency.
  Future<void> decode(EncodedVideoFrame frame);

  /// Releases the decoder and its Flutter texture.
  ///
  /// Disposal must be idempotent and wait for any in-flight [decode] operation.
  Future<void> dispose();
}

typedef VideoDecoderFactory = Future<VideoDecoder> Function(
  VideoStreamConfiguration configuration,
);
