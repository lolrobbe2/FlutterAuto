import 'dart:typed_data';

/// One complete H.264/H.265 Annex-B access unit.
///
/// Keyframes must carry the codec parameter sets required to initialize a
/// decoder (SPS/PPS for H.264; VPS/SPS/PPS for H.265). [data] is not copied.
/// The producer must not mutate the buffer until its send operation completes.
/// Timestamps use monotonic microseconds, not wall-clock time.
class EncodedVideoFrame {
  final int sequenceNumber;
  final int presentationTimeMicros;
  final bool isKeyFrame;
  final Uint8List data;

  EncodedVideoFrame({
    required this.sequenceNumber,
    required this.presentationTimeMicros,
    required this.isKeyFrame,
    required this.data,
  }) {
    if (sequenceNumber < 0 || sequenceNumber > 0x7fffffffffffffff) {
      throw ArgumentError.value(sequenceNumber, 'sequenceNumber');
    }
    if (presentationTimeMicros < 0 ||
        presentationTimeMicros > 0x7fffffffffffffff) {
      throw ArgumentError.value(
        presentationTimeMicros,
        'presentationTimeMicros',
      );
    }
    if (data.isEmpty) {
      throw ArgumentError.value(
        data,
        'data',
        'An access unit cannot be empty.',
      );
    }
  }
}
