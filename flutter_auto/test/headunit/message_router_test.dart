import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_auto/headunit/message_router.dart';
import 'package:flutter_auto/headunit/protocol_connection.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ServerSocket server;
  late Socket peerSocket;
  late ProtocolConnection connection;
  late MessageRouter router;

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

    final Future<Socket> acceptedSocket = server.first;
    final Socket clientSocket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
    );

    peerSocket = await acceptedSocket;
    connection = ProtocolConnection(clientSocket);
    router = MessageRouter(connection);
  });

  tearDown(() async {
    peerSocket.destroy();
    await router.close().timeout(const Duration(seconds: 2));
    await connection.close().timeout(const Duration(seconds: 2));
    await server.close();
  });

  ProtocolFrame createControlFrame(int messageId) {
    final Uint8List payload = Uint8List(4);
    final ByteData data = ByteData.sublistView(payload);

    data.setUint16(0, messageId, Endian.big);
    data.setUint16(2, 0x1234, Endian.big);

    return ProtocolFrame(
      channel: 0,
      frameType: FrameType.bulk,
      messageType: MessageType.control,
      encryptionType: EncryptionType.plain,
      payload: payload,
    );
  }

  Future<void> sendFrame(ProtocolFrame frame) async {
    peerSocket.add(frame.encode());
    await peerSocket.flush();
  }

  test('broadcasts a message to multiple listeners', () async {
    final Completer<int> firstListener = Completer<int>();
    final Completer<int> secondListener = Completer<int>();

    final StreamSubscription<dynamic> firstSubscription = router.messages
        .listen((message) {
          if (!firstListener.isCompleted) {
            firstListener.complete(message.payload.length);
          }
        });

    final StreamSubscription<dynamic> secondSubscription = router.messages
        .listen((message) {
          if (!secondListener.isCompleted) {
            secondListener.complete(message.payload.length);
          }
        });

    await sendFrame(createControlFrame(1));

    expect(await firstListener.future.timeout(const Duration(seconds: 5)), 4);
    expect(await secondListener.future.timeout(const Duration(seconds: 5)), 4);

    await firstSubscription.cancel();
    await secondSubscription.cancel();
  });

  test('filters messages by message ID and channel', () async {
    final Completer<int> responseCompleter = Completer<int>();

    final StreamSubscription<dynamic> subscription = router
        .forMessageId(2, channel: 0)
        .listen((message) {
          if (!responseCompleter.isCompleted) {
            responseCompleter.complete(message.channel);
          }
        });

    await sendFrame(createControlFrame(1));
    await sendFrame(createControlFrame(2));

    expect(
      await responseCompleter.future.timeout(const Duration(seconds: 5)),
      0,
    );

    await subscription.cancel();
  });

  test('preserves the original payload including the message ID', () async {
    final Completer<Uint8List> payloadCompleter = Completer<Uint8List>();

    final StreamSubscription<dynamic> subscription = router
        .forMessageId(2, channel: 0)
        .listen((message) {
          if (!payloadCompleter.isCompleted) {
            payloadCompleter.complete(message.payload);
          }
        });

    await sendFrame(createControlFrame(2));

    final Uint8List payload = await payloadCompleter.future.timeout(
      const Duration(seconds: 5),
    );

    final ByteData data = ByteData.sublistView(payload);

    expect(data.getUint16(0, Endian.big), 2);
    expect(data.getUint16(2, Endian.big), 0x1234);

    await subscription.cancel();
  });

  test('rejects message IDs outside the unsigned 16-bit range', () {
    expect(() => router.forMessageId(65536), throwsArgumentError);

    expect(() => router.forMessageId(-1), throwsArgumentError);
  });

  test('closes cleanly', () async {
    await router.close();

    expect(router.isClosed, isTrue);
  });
}
