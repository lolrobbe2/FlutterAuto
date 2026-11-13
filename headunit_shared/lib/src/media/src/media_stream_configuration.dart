/// Video codecs supported by the initial remote-application media protocol.
enum VideoCodec {
  h264(1),
  h265(2);

  final int wireValue;
  const VideoCodec(this.wireValue);

  static VideoCodec fromWireValue(int value) {
    for (final VideoCodec codec in VideoCodec.values) {
      if (codec.wireValue == value) {
        return codec;
      }
    }
    throw FormatException('Unsupported video codec: $value.');
  }
}

/// Host-selected encoded-video stream parameters.
///
/// The wire format is Annex-B access units. Native encoders must convert their
/// output to Annex-B before submitting it to [MediaStreamClient.sendFrame].
class VideoStreamConfiguration {
  final VideoCodec codec;
  final int width;
  final int height;
  final int framesPerSecond;
  final int targetBitrateBitsPerSecond;
  final int rotationDegrees;

  const VideoStreamConfiguration({
    required this.codec,
    required this.width,
    required this.height,
    required this.framesPerSecond,
    required this.targetBitrateBitsPerSecond,
    this.rotationDegrees = 0,
  });

  /// Conservative default for lower-memory embedded headunits.
  static const VideoStreamConfiguration defaultConfiguration =
      VideoStreamConfiguration(
        codec: VideoCodec.h264,
        width: 800,
        height: 480,
        framesPerSecond: 30,
        targetBitrateBitsPerSecond: 1500000,
      );

  void validate() {
    if (width < 1 || width > 8192) {
      throw ArgumentError.value(width, 'width');
    }
    if (height < 1 || height > 8192) {
      throw ArgumentError.value(height, 'height');
    }
    if (framesPerSecond < 1 || framesPerSecond > 120) {
      throw ArgumentError.value(framesPerSecond, 'framesPerSecond');
    }
    if (targetBitrateBitsPerSecond < 64000 ||
        targetBitrateBitsPerSecond > 100000000) {
      throw ArgumentError.value(
        targetBitrateBitsPerSecond,
        'targetBitrateBitsPerSecond',
      );
    }
    if (rotationDegrees != 0 &&
        rotationDegrees != 90 &&
        rotationDegrees != 180 &&
        rotationDegrees != 270) {
      throw ArgumentError.value(rotationDegrees, 'rotationDegrees');
    }
  }
}
