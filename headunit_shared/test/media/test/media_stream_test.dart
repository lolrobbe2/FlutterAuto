import 'dart:async';
import 'dart:typed_data';

import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:test/test.dart';

void main() {
  group('VideoStreamConfiguration', () {
    test('validates and preserves the negotiated configuration', () async {
      const VideoStreamConfiguration configuration =
          VideoStreamConfiguration.defaultConfiguration;
      configuration.validate();
      expect(configuration.codec, VideoCodec.h264);
      expect(configuration.width, 800);
      expect(configuration.height, 480);
      expect(configuration.framesPerSecond, 30);
    });

    test('rejects invalid dimensions and bitrate', () {
      expect(
        () => const VideoStreamConfiguration(
          codec: VideoCodec.h264,
          width: 0,
          height: 720,
          framesPerSecond: 30,
          targetBitrateBitsPerSecond: 1000000,
        ).validate(),
        throwsArgumentError,
      );
      expect(
        () => const VideoStreamConfiguration(
          codec: VideoCodec.h264,
          width: 1280,
          height: 720,
          framesPerSecond: 30,
          targetBitrateBitsPerSecond: 0,
        ).validate(),
        throwsArgumentError,
      );
    });
  });

  group('LocalMediaServer', () {
    late LocalMediaServer server;
    const String token = '0123456789abcdef0123456789abcdef';

    setUp(() async {
      server = await LocalMediaServer.bind(
        token: token,
        configuration: const VideoStreamConfiguration(
          codec: VideoCodec.h264,
          width: 640,
          height: 480,
          framesPerSecond: 30,
          targetBitrateBitsPerSecond: 1500000,
        ),
        maxQueuedFrames: 1,
      );
    });

    tearDown(() async {
      await server.close();
    });

    test('authenticates, negotiates and transfers a compressed access unit',
        () async {
      final Future<MediaStreamConnection> accepted = server.connections.first;
      final MediaStreamClient client = await MediaStreamClient.connect(
        host: server.host,
        port: server.port,
        token: token,
      );
      final MediaStreamConnection hostConnection = await accepted;

      expect(client.configuration.width, 640);
      expect(client.configuration.height, 480);
      expect(client.requiresKeyFrame, isTrue);

      await client.sendFrame(
        EncodedVideoFrame(
          sequenceNumber: 0,
          presentationTimeMicros: 0,
          isKeyFrame: true,
          data: Uint8List.fromList(<int>[0, 0, 0, 1, 0x65, 1, 2]),
        ),
      );
      final EncodedVideoFrame? received = await hostConnection
          .nextFrame()
          .timeout(const Duration(seconds: 2));
      expect(received, isNotNull);
      expect(received!.isKeyFrame, isTrue);
      expect(received.sequenceNumber, 0);
      expect(received.data, <int>[0, 0, 0, 1, 0x65, 1, 2]);

      await client.close();
    });

    test('rejects an incorrect session token', () async {
      await expectLater(
        MediaStreamClient.connect(
          host: server.host,
          port: server.port,
          token: 'fedcba9876543210fedcba9876543210',
        ),
        throwsA(isA<MediaTransportException>()),
      );
    });

    test('requests a keyframe when the bounded frame queue overflows',
        () async {
      final Future<MediaStreamConnection> accepted = server.connections.first;
      final MediaStreamClient client = await MediaStreamClient.connect(
        host: server.host,
        port: server.port,
        token: token,
      );
      final MediaStreamConnection hostConnection = await accepted;
      final Completer<void> keyFrameRequested = Completer<void>();
      final StreamSubscription<void> subscription =
          client.keyFrameRequests.listen((_) {
        if (!keyFrameRequested.isCompleted) {
          keyFrameRequested.complete();
        }
      });

      await client.sendFrame(
        EncodedVideoFrame(
          sequenceNumber: 0,
          presentationTimeMicros: 0,
          isKeyFrame: true,
          data: Uint8List.fromList(<int>[1]),
        ),
      );
      await client.sendFrame(
        EncodedVideoFrame(
          sequenceNumber: 1,
          presentationTimeMicros: 33333,
          isKeyFrame: false,
          data: Uint8List.fromList(<int>[2]),
        ),
      );

      await keyFrameRequested.future.timeout(const Duration(seconds: 2));
      expect(client.requiresKeyFrame, isTrue);
      await expectLater(
        client.sendFrame(
          EncodedVideoFrame(
            sequenceNumber: 2,
            presentationTimeMicros: 66666,
            isKeyFrame: false,
            data: Uint8List.fromList(<int>[3]),
          ),
        ),
        throwsStateError,
      );

      await client.sendFrame(
        EncodedVideoFrame(
          sequenceNumber: 2,
          presentationTimeMicros: 66666,
          isKeyFrame: true,
          data: Uint8List.fromList(<int>[4]),
        ),
      );
      final EncodedVideoFrame? recovered = await hostConnection
          .nextFrame()
          .timeout(const Duration(seconds: 2));
      expect(recovered, isNotNull);
      expect(recovered!.isKeyFrame, isTrue);
      expect(recovered.sequenceNumber, 2);
      expect(hostConnection.droppedFrames, greaterThanOrEqualTo(2));

      await subscription.cancel();
      await client.close();
    });
  });
}
