import 'dart:async';

import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:test/test.dart';

void main() {
  group('RpcConnection', () {
    late LocalRpcServer server;
    late RpcConnection client;
    late RpcConnection serverConnection;

    setUp(() async {
      server = await LocalRpcServer.bind(maxConnections: 1);
      final Future<RpcConnection> accepted = server.connections.first;
      client = await RpcConnection.connect(
        host: server.host,
        port: server.port,
      );
      serverConnection = await accepted;
    });

    tearDown(() async {
      await client.close();
      await server.close();
    });

    test('round-trips a request and response', () async {
      serverConnection.registerRequestHandler('math.add', (parameters) {
        final int left = parameters['left']! as int;
        final int right = parameters['right']! as int;
        return left + right;
      });

      final Object? result = await client.request(
        'math.add',
        parameters: <String, Object?>{'left': 20, 'right': 22},
      );

      expect(result, 42);
    });

    test('delivers notifications without a response', () async {
      final Future<RpcNotification> notification =
          serverConnection.notifications.first;

      client.notify(
        'input.pointer.down',
        parameters: <String, Object?>{'x': 0.25, 'y': 0.75},
      );

      final RpcNotification received = await notification;
      expect(received.method, 'input.pointer.down');
      expect(received.parameters['x'], 0.25);
      expect(received.parameters['y'], 0.75);
    });

    test('returns a method-not-found error', () async {
      await expectLater(
        client.request('missing.method'),
        throwsA(
          isA<RpcException>().having(
            (RpcException error) => error.code,
            'code',
            -32601,
          ),
        ),
      );
    });
  });
}
