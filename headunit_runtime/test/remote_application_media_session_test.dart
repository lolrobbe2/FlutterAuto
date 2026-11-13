import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:headunit_media/headunit_media.dart';
import 'package:headunit_runtime/src/application/remote_application_rpc_session.dart';
import 'package:headunit_runtime/src/services/service_registry.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

void main() {
  group('Remote application media session', () {
    late ServiceRegistry registry;
    late RemoteApplicationRpcSession session;
    late HeadunitConnection connection;

    setUp(() async {
      registry = ServiceRegistry();
      final ApplicationLaunchContext context = ApplicationLaunchContext(
        applicationId: ApplicationId('com.example.video'),
      );
      session = await RemoteApplicationRpcSession.bind(
        context: context,
        serviceBroker: registry.createBroker(context),
        mediaConfiguration: const VideoStreamConfiguration(
          codec: VideoCodec.h264,
          width: 800,
          height: 480,
          framesPerSecond: 30,
          targetBitrateBitsPerSecond: 2000000,
        ),
      );
      final RemoteApplicationEndpoint endpoint = session.endpoint;
      connection = await HeadunitConnection.connect(
        host: endpoint.host,
        port: endpoint.port,
        mediaPort: endpoint.mediaPort,
        token: endpoint.token,
      );
    });

    tearDown(() async {
      await connection.close();
      await session.dispose();
      registry.dispose();
    });

    test('opens separate media channel and transfers an IDR access unit',
        () async {
      final Future<MediaStreamConnection> accepted =
          session.mediaConnections.first;
      final MediaStreamClient appMedia = await connection.openMediaStream();
      final MediaStreamConnection hostMedia = await accepted;

      expect(appMedia.configuration.width, 800);
      expect(appMedia.configuration.height, 480);
      expect(appMedia.requiresKeyFrame, isTrue);

      await appMedia.sendFrame(
        EncodedVideoFrame(
          sequenceNumber: 0,
          presentationTimeMicros: 0,
          isKeyFrame: true,
          data: Uint8List.fromList(<int>[0, 0, 0, 1, 0x65]),
        ),
      );

      final EncodedVideoFrame? frame = await hostMedia
          .nextFrame()
          .timeout(const Duration(seconds: 2));
      expect(frame, isNotNull);
      expect(frame!.isKeyFrame, isTrue);
      expect(frame.data, <int>[0, 0, 0, 1, 0x65]);
    });
  });
}
