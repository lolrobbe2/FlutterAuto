import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_runtime/headunit_runtime.dart';

void main() {
  group('FfmpegVideoDecoder.buildPlayerArguments', () {
    const VideoStreamConfiguration h264Configuration = VideoStreamConfiguration(
      codec: VideoCodec.h264,
      width: 800,
      height: 480,
      framesPerSecond: 30,
      targetBitrateBitsPerSecond: 1500000,
    );

    const VideoStreamConfiguration h265Configuration = VideoStreamConfiguration(
      codec: VideoCodec.h265,
      width: 1280,
      height: 720,
      framesPerSecond: 25,
      targetBitrateBitsPerSecond: 2500000,
    );

    final Uri inputUri = Uri(
      scheme: 'tcp',
      host: '127.0.0.1',
      port: 43123,
      queryParameters: const <String, String>{'tcp_nodelay': '1'},
    );

    test('configures raw H.264 input and the configured frame rate', () {
      final List<String> arguments = FfmpegVideoDecoder.buildPlayerArguments(
        h264Configuration,
        inputUri,
      );

      expect(arguments[arguments.indexOf('-f') + 1], 'h264');
      expect(arguments[arguments.indexOf('-i') + 1], inputUri.toString());
      expect(arguments, containsAll(<String>['-an', '-sn', '-dn']));
      expect(arguments, contains('-framedrop'));
      // Do not force -hwaccel: the Windows FFplay texture path selects its
      // supported renderer itself, and forcing hardware decoding can break it.
      expect(arguments, isNot(contains('-hwaccel')));
    });

    test(
      'configures raw HEVC input and preserves the configured frame rate',
      () {
        final List<String> arguments = FfmpegVideoDecoder.buildPlayerArguments(
          h265Configuration,
          inputUri,
        );

        expect(arguments[arguments.indexOf('-f') + 1], 'hevc');
        expect(arguments[arguments.indexOf('-i') + 1], inputUri.toString());
      },
    );

    test('adds the requested rotation filter', () {
      const VideoStreamConfiguration rotatedConfiguration =
          VideoStreamConfiguration(
            codec: VideoCodec.h264,
            width: 800,
            height: 480,
            framesPerSecond: 30,
            targetBitrateBitsPerSecond: 1500000,
            rotationDegrees: 90,
          );

      final List<String> arguments = FfmpegVideoDecoder.buildPlayerArguments(
        rotatedConfiguration,
        inputUri,
      );

      expect(arguments[arguments.indexOf('-vf') + 1], 'transpose=clock');
    });

    test('rejects a non-loopback input URI', () {
      expect(
        () => FfmpegVideoDecoder.buildPlayerArguments(
          h264Configuration,
          Uri.parse('tcp://192.168.1.10:43123'),
        ),
        throwsArgumentError,
      );
    });
  });
}
