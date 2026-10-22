import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_auto/generated/oaa/control/ControlMessageIdsEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/control/VersionResponseStatusEnum.pbenum.dart';
import 'package:flutter_auto/headunit/message_router.dart';
import 'package:flutter_auto/headunit/protocol_connection.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';
import 'package:flutter_auto/headunit/version_handshake.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ServerSocket server;
  late Socket phoneSocket;
  late ProtocolConnection connection;
  late MessageRouter router;
  late StreamSubscription<List<int>> phoneSubscription;
  late Completer<ProtocolFrame> requestCompleter;
  late List<int> receivedBytes;

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

    final Future<Socket> acceptedSocket = server.first;

    final Socket headUnitSocket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
    );

    phoneSocket = await acceptedSocket;
    connection = ProtocolConnection(headUnitSocket);
    router = MessageRouter(connection);

    requestCompleter = Completer<ProtocolFrame>();
    receivedBytes = <int>[];

    phoneSubscription = phoneSocket.listen((List<int> data) {
      receivedBytes.addAll(data);

      if (receivedBytes.length < 4 || requestCompleter.isCompleted) {
        return;
      }

      final int payloadLength = (receivedBytes[2] << 8) | receivedBytes[3];
      final int frameLength = 4 + payloadLength;

      if (receivedBytes.length >= frameLength) {
        final Uint8List frameBytes = Uint8List.fromList(
          receivedBytes.sublist(0, frameLength),
        );

        requestCompleter.complete(ProtocolFrame.decode(frameBytes, messageType: MessageType.control));
      }
    });
  });

  tearDown(() async {
    await router.close();
    await connection.close();
    await phoneSubscription.cancel();
    phoneSocket.destroy();
    await server.close();
  });

  test('sends version request and parses successful response', () async {
    final VersionHandshake handshake = VersionHandshake(
      connection: connection,
      router: router,
      supportedMajorVersion: 1,
      supportedMinorVersion: 1,
    );

    // Start the handshake before waiting for the request.
    final Future<VersionHandshakeResult> handshakeFuture = handshake.run();

    final ProtocolFrame request = await requestCompleter.future.timeout(
      const Duration(seconds: 5),
    );

    expect(request.channel, 0);
    expect(request.frameType, FrameType.bulk);
    expect(request.messageType, MessageType.control);
    expect(request.encryptionType, EncryptionType.plain);

    final ByteData requestData = ByteData.sublistView(request.payload);

    expect(
      requestData.getUint16(0, Endian.big),
      ControlMessage_Enum.VERSION_REQUEST.value,
    );
    expect(requestData.getUint16(2, Endian.big), 1);
    expect(requestData.getUint16(4, Endian.big), 1);

    // Simulate the phone returning VERSION_RESPONSE.
    final Uint8List responsePayload = Uint8List(8);
    final ByteData responseData = ByteData.sublistView(responsePayload);

    responseData.setUint16(
      0,
      ControlMessage_Enum.VERSION_RESPONSE.value,
      Endian.big,
    );
    responseData.setUint16(2, 1, Endian.big);
    responseData.setUint16(4, 1, Endian.big);
    responseData.setUint16(
      6,
      ProtocolStatus_Enum.STATUS_SUCCESS.value,
      Endian.big,
    );

    final ProtocolFrame response = ProtocolFrame(
      channel: 0,
      frameType: FrameType.bulk,
      messageType: MessageType.control,
      encryptionType: EncryptionType.plain,
      payload: responsePayload,
    );

    phoneSocket.add(response.encode());
    await phoneSocket.flush();

    final VersionHandshakeResult result = await handshakeFuture.timeout(
      const Duration(seconds: 5),
    );

    expect(result.majorVersion, 1);
    expect(result.minorVersion, 1);
    expect(result.status, ProtocolStatus_Enum.STATUS_SUCCESS);
  });
}
