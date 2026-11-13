import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:test/test.dart';

void main() {
  group('MediaFrameSubscription', () {
    test('cancellation completes a pending read and keeps connection open',
        () async {
      const String token = '0123456789abcdef0123456789abcdef';
      final LocalMediaServer server = await LocalMediaServer.bind(
        token: token,
      );
      final Future<MediaStreamConnection> accepting = server.connections.first;
      final MediaStreamClient client = await MediaStreamClient.connect(
        host: server.host,
        port: server.port,
        token: token,
      );
      final MediaStreamConnection connection = await accepting;
      final MediaFrameSubscription subscription =
          connection.createFrameSubscription();
      final Future<EncodedVideoFrame?> pending = subscription.nextFrame();

      subscription.cancel();

      expect(await pending, isNull);
      expect(subscription.isCancelled, isTrue);
      expect(connection.isClosed, isFalse);

      final MediaFrameSubscription secondSubscription =
          connection.createFrameSubscription();
      secondSubscription.cancel();

      await client.close();
      await server.close();
    });
  });
}
