import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ServiceDiscoveryRequestMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ServiceDiscoveryResponseMessage.pb.dart';
import 'package:flutter_auto/headunit/message_router.dart';
import 'package:flutter_auto/headunit/protocol_connection.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';
import 'package:flutter_auto/headunit/protocol_message.dart';
import 'package:flutter_auto/headunit/service/service_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceManager discovery', () {
    late _Harness harness;
    late ServiceManager manager;

    setUp(() {
      harness = _Harness();
      manager = harness.createManager(
        headUnitName: 'Test Head Unit',
        carModel: 'Test Car',
        headunitManufacturer: 'Test Manufacturer',
        headunitModel: 'Model X',
        swVersion: '2.0.0',
      );
    });

    tearDown(() async {
      await manager.dispose();
      await harness.dispose();
    });

    test('sends 0x0006 before receiving the phone 0x0005 request', () async {
      manager.registerService(
        name: 'media',
        channelId: 3,
        buildDescriptor: _descriptor,
      );
      manager.registerService(
        name: 'phone-status',
        channelId: 5,
        buildDescriptor: _descriptor,
      );

      manager.start();

      // No phone request has been sent yet.
      final response = await manager.discover();

      expect(harness.sentPayloads, hasLength(1));

      final Uint8List payload = harness.sentPayloads.single;
      expect(_messageId(payload), ServiceManager.serviceDiscoveryResponseId);

      final parsed = ServiceDiscoveryResponse.fromBuffer(payload.sublist(2));

      expect(parsed.headUnitName, 'Test Head Unit');
      expect(parsed.carModel, 'Test Car');
      expect(parsed.headunitManufacturer, 'Test Manufacturer');
      expect(parsed.headunitModel, 'Model X');
      expect(parsed.swVersion, '2.0.0');

      expect(parsed.channels, hasLength(2));
      expect(
        parsed.channels.map((ChannelDescriptor c) => c.channelId),
        containsAll(<int>[3, 5]),
      );
      expect(response.channels, hasLength(2));
      expect(manager.discoveryCompleted, isTrue);
      expect(manager.requestReceived, isFalse);

      // The phone sends its request only after the HU has advertised its channels.
      harness.sendDiscoveryRequest(
        ServiceDiscoveryRequest()
          ..deviceName = 'Test Phone'
          ..deviceBrand = 'Test Brand',
      );

      final phoneRequest = await manager.waitForPhoneRequest();

      expect(phoneRequest.deviceName, 'Test Phone');
      expect(phoneRequest.deviceBrand, 'Test Brand');

      // Receiving 0x0005 must not cause a second 0x0006.
      expect(harness.sentPayloads, hasLength(1));
      expect(manager.requestReceived, isTrue);
    });

    test('uses the registered channel ID in each descriptor', () async {
      manager.registerService(
        name: 'media',
        channelId: 17,
        buildDescriptor: (int _) => ChannelDescriptor()..channelId = 99,
      );

      manager.start();
      final response = await manager.discover();

      expect(response.channels, hasLength(1));
      expect(response.channels.single.channelId, 17);

      final payload = harness.sentPayloads.single;
      final parsed = ServiceDiscoveryResponse.fromBuffer(payload.sublist(2));

      expect(parsed.channels.single.channelId, 17);
    });

    test('includes no channels when no services are registered', () async {
      manager.start();

      final response = await manager.discover();

      expect(response.channels, isEmpty);
      expect(harness.sentPayloads, hasLength(1));
      expect(
        _messageId(harness.sentPayloads.single),
        ServiceManager.serviceDiscoveryResponseId,
      );
      expect(manager.discoveryCompleted, isTrue);
    });

    test(
      'does not send discovery response for messages on another channel',
      () async {
        manager.start();

        harness.sendMessage(
          channel: 1,
          payload: _requestPayload(ServiceDiscoveryRequest()),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(harness.sentPayloads, isEmpty);
        expect(manager.discoveryCompleted, isFalse);
      },
    );

    test(
      'does not send discovery response for a different message ID',
      () async {
        manager.start();

        harness.sendMessage(
          channel: 0,
          payload: Uint8List.fromList(<int>[0, 99, 1, 2, 3]),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(harness.sentPayloads, isEmpty);
        expect(manager.discoveryCompleted, isFalse);
      },
    );

    test(
      'does not send a second response when the phone request arrives',
      () async {
        manager.start();
        await manager.discover();

        harness.sendDiscoveryRequest(ServiceDiscoveryRequest());

        await manager.waitForPhoneRequest();

        expect(harness.sentPayloads, hasLength(1));
        expect(manager.discoveryCompleted, isTrue);
        expect(manager.requestReceived, isTrue);
      },
    );

    test('rejects a second discovery response send', () async {
      manager.start();
      await manager.discover();

      await expectLater(manager.discover(), throwsStateError);

      expect(harness.sentPayloads, hasLength(1));
    });

    test('dispose stops handling new requests', () async {
      manager.start();
      await manager.discover();

      await manager.dispose();

      harness.sendDiscoveryRequest(ServiceDiscoveryRequest());

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(harness.sentPayloads, hasLength(1));
      expect(manager.isStarted, isFalse);
    });
  });
}

ChannelDescriptor _descriptor(int channelId) {
  return ChannelDescriptor()..channelId = channelId;
}

int _messageId(Uint8List payload) {
  if (payload.length < 2) {
    throw const FormatException('Payload is missing its message ID.');
  }

  return ByteData.sublistView(payload).getUint16(0, Endian.big);
}

Uint8List _requestPayload(ServiceDiscoveryRequest request) {
  final Uint8List body = request.writeToBuffer();
  final Uint8List payload = Uint8List(body.length + 2);

  ByteData.sublistView(
    payload,
  ).setUint16(0, ServiceManager.serviceDiscoveryRequestId, Endian.big);

  payload.setRange(2, payload.length, body);
  return payload;
}

/// A small in-memory harness; no socket or phone connection is required.
class _Harness {
  final StreamController<ProtocolMessage> _messages =
      StreamController<ProtocolMessage>();

  final List<Uint8List> sentPayloads = <Uint8List>[];
  final List<Completer<Uint8List>> _pendingWaiters = <Completer<Uint8List>>[];

  late final MessageRouter router = MessageRouter(
    _FakeProtocolConnection(_messages.stream),
  );

  ServiceManager createManager({
    String headUnitName = 'FlutterAuto',
    String carModel = '',
    String headunitManufacturer = '',
    String headunitModel = '',
    String swVersion = '1.0.0',
  }) {
    return ServiceManager(
      router: router,
      headUnitName: headUnitName,
      carModel: carModel,
      headunitManufacturer: headunitManufacturer,
      headunitModel: headunitModel,
      swVersion: swVersion,
      sendControlPayload: (Uint8List payload) async {
        final Uint8List copy = Uint8List.fromList(payload);
        sentPayloads.add(copy);

        if (_pendingWaiters.isNotEmpty) {
          final Completer<Uint8List> waiter = _pendingWaiters.removeAt(0);
          if (!waiter.isCompleted) {
            waiter.complete(copy);
          }
        }
      },
    );
  }

  Future<Uint8List> nextSentPayload() {
    if (sentPayloads.isNotEmpty) {
      return Future<Uint8List>.value(sentPayloads.last);
    }

    final Completer<Uint8List> completer = Completer<Uint8List>();
    _pendingWaiters.add(completer);

    return completer.future.timeout(const Duration(seconds: 2));
  }

  void sendDiscoveryRequest(ServiceDiscoveryRequest request) {
    sendMessage(channel: 0, payload: _requestPayload(request));
  }

  void sendMessage({required int channel, required Uint8List payload}) {
    _messages.add(
      ProtocolMessage(
        channel: channel,
        messageType: channel == 0 ? MessageType.control : MessageType.specific,
        encryptionType: EncryptionType.plain,
        payload: payload,
      ),
    );
  }

  Future<void> waitForDiscovery(ServiceManager manager) async {
    for (int i = 0; i < 100; i++) {
      if (manager.discoveryCompleted) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    fail('Service discovery did not complete in time.');
  }

  Future<void> dispose() async {
    for (final Completer<Uint8List> waiter in _pendingWaiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(
          StateError('Test harness disposed before a payload was sent.'),
        );
      }
    }
    _pendingWaiters.clear();

    await router.close();
    await _messages.close();
  }
}

class _FakeProtocolConnection implements ProtocolConnection {
  _FakeProtocolConnection(this._messages);

  final Stream<ProtocolMessage> _messages;

  @override
  Stream<ProtocolMessage> get messages => _messages;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
