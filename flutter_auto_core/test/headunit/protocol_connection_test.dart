import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_auto_core/flutter_auto_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProtocolConnection', () {
    late ServerSocket server;
    late Socket clientSocket;
    late Socket serverSocket;
    late ProtocolConnection connection;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

      final Future<Socket> acceptedSocket = server.first;
      clientSocket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      serverSocket = await acceptedSocket;

      connection = ProtocolConnection(clientSocket);
    });

    tearDown(() async {
      await connection.close();
      serverSocket.destroy();
      await server.close();
    });

    ProtocolFrame createFrame(List<int> payload) {
      return ProtocolFrame(
        channel: 0,
        frameType: FrameType.bulk,
        messageType: MessageType.control,
        encryptionType: EncryptionType.plain,
        payload: Uint8List.fromList(payload),
      );
    }

    test('decodes a complete frame', () async {
      final ProtocolFrame expected = createFrame(<int>[1, 2, 3]);
      final Future<ProtocolFrame> received = connection.frames.first;

      serverSocket.add(expected.encode());
      await serverSocket.flush();

      final ProtocolFrame actual = await received.timeout(
        const Duration(seconds: 2),
      );

      expect(actual.channel, expected.channel);
      expect(actual.payload, expected.payload);
      expect(actual.frameType, expected.frameType);
    });

    test('buffers a partial frame until the rest arrives', () async {
      final ProtocolFrame expected = createFrame(<int>[1, 2, 3, 4]);
      final Uint8List encoded = expected.encode();
      final Future<ProtocolFrame> received = connection.frames.first;

      serverSocket.add(encoded.sublist(0, 3));
      await serverSocket.flush();

      // Give the receiver an opportunity to process the incomplete bytes.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      serverSocket.add(encoded.sublist(3));
      await serverSocket.flush();

      final ProtocolFrame actual = await received.timeout(
        const Duration(seconds: 2),
      );

      expect(actual.payload, expected.payload);
    });

    test('emits multiple frames from one TCP write', () async {
      final ProtocolFrame first = createFrame(<int>[10]);
      final ProtocolFrame second = createFrame(<int>[20, 30]);

      final List<ProtocolFrame> received = <ProtocolFrame>[];
      final Future<void> completed = connection.frames
          .take(2)
          .forEach(received.add);

      serverSocket.add(<int>[...first.encode(), ...second.encode()]);
      await serverSocket.flush();

      await completed.timeout(const Duration(seconds: 2));

      expect(received, hasLength(2));
      expect(received[0].payload, <int>[10]);
      expect(received[1].payload, <int>[20, 30]);
    });

    test('sends an encoded frame to the socket', () async {
      final ProtocolFrame expected = createFrame(<int>[1, 2, 3, 4]);
      final Uint8List expectedBytes = expected.encode();

      final Completer<Uint8List> receivedCompleter = Completer<Uint8List>();
      final List<int> receivedBytes = <int>[];

      final StreamSubscription<List<int>> subscription = serverSocket.listen(
        (List<int> data) {
          receivedBytes.addAll(data);

          if (receivedBytes.length >= expectedBytes.length &&
              !receivedCompleter.isCompleted) {
            receivedCompleter.complete(
              Uint8List.fromList(
                receivedBytes.sublist(0, expectedBytes.length),
              ),
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!receivedCompleter.isCompleted) {
            receivedCompleter.completeError(error, stackTrace);
          }
        },
      );

      try {
        await connection.send(expected);

        final Uint8List actualBytes = await receivedCompleter.future.timeout(
          const Duration(seconds: 5),
        );

        expect(actualBytes, equals(expectedBytes));
      } finally {
        await subscription.cancel();
      }
    });

    test('close marks the connection as closed', () async {
      await connection.close();

      expect(connection.isClosed, isTrue);
    });
    test(
      'serializes concurrent sends without corrupting frame order',
      () async {
        const int frameCount = 100;

        final List<ProtocolFrame> frames = List<ProtocolFrame>.generate(
          frameCount,
          (int index) =>
              createFrame(<int>[(index >> 8) & 0xFF, index & 0xFF, 0xAA, 0x55]),
        );

        // Expected stream is all encoded frames concatenated in send order.
        final List<int> expectedBytes = frames
            .expand((ProtocolFrame frame) => frame.encode())
            .toList();

        final Completer<Uint8List> receivedCompleter = Completer<Uint8List>();
        final List<int> receivedBytes = <int>[];

        final StreamSubscription<List<int>> subscription = serverSocket.listen(
          (List<int> data) {
            receivedBytes.addAll(data);

            if (receivedBytes.length >= expectedBytes.length &&
                !receivedCompleter.isCompleted) {
              receivedCompleter.complete(
                Uint8List.fromList(
                  receivedBytes.sublist(0, expectedBytes.length),
                ),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!receivedCompleter.isCompleted) {
              receivedCompleter.completeError(error, stackTrace);
            }
          },
        );

        try {
          // Schedule every send without waiting for the previous one.
          // The ProtocolConnection write queue must serialize them.
          await Future.wait(
            frames.map((ProtocolFrame frame) => connection.send(frame)),
          );

          final Uint8List actualBytes = await receivedCompleter.future.timeout(
            const Duration(seconds: 5),
          );

          expect(actualBytes, equals(expectedBytes));
        } finally {
          await subscription.cancel();
        }
      },
    );
  });
}
