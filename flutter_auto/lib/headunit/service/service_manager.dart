import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_auto/generated/oaa/common/DriverPositionEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ServiceDiscoveryRequestMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ServiceDiscoveryResponseMessage.pb.dart';
import 'package:flutter_auto/headunit/message_router.dart';
import 'package:logging/logging.dart';

typedef ControlPayloadSender = Future<void> Function(Uint8List payload);
typedef ChannelDescriptorBuilder = ChannelDescriptor Function(int channelId);

class RegisteredService {
  const RegisteredService({
    required this.name,
    required this.channelId,
    required this.buildDescriptor,
  });

  final String name;
  final int channelId;
  final ChannelDescriptorBuilder buildDescriptor;
}

class ServiceManager {
  ServiceManager({
    required MessageRouter router,
    required ControlPayloadSender sendControlPayload,
    this.headUnitName = 'FlutterAuto',
    this.carModel = '',
    this.headunitManufacturer = '',
    this.headunitModel = '',
    this.swVersion = '1.0.0',
  }) : _router = router,
       _sendControlPayload = sendControlPayload;

  static const int controlChannel = 0;
  static const int serviceDiscoveryRequestId = 0x0005;
  static const int serviceDiscoveryResponseId = 0x0006;

  final MessageRouter _router;
  final ControlPayloadSender _sendControlPayload;
  final Logger _log = Logger('ServiceManager');

  // Head-unit metadata advertised in SERVICE_DISCOVERY_RESPONSE.
  final String headUnitName;
  final String carModel;
  final String headunitManufacturer;
  final String headunitModel;
  final String swVersion;

  final Map<int, RegisteredService> _servicesByChannel = {};
  final Map<String, int> _channelsByName = {};

  StreamSubscription<dynamic>? _subscription;
  Completer<ServiceDiscoveryRequest>? _requestCompleter;

  bool _started = false;
  bool _disposed = false;
  bool _requestReceived = false;
  bool _discoveryCompleted = false;

  ServiceDiscoveryRequest? phoneRequest;
  ServiceDiscoveryResponse? localDiscoveryResponse;

  bool get isStarted => _started;
  bool get requestReceived => _requestReceived;
  bool get discoveryCompleted => _discoveryCompleted;

  List<RegisteredService> get registeredServices =>
      List.unmodifiable(_servicesByChannel.values);

  int registerService({
    required String name,
    required ChannelDescriptorBuilder buildDescriptor,
    int? channelId,
  }) {
    _checkNotDisposed();

    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }
    if (_channelsByName.containsKey(name)) {
      throw StateError('Service "$name" is already registered.');
    }

    final assignedChannel = channelId ?? _allocateChannelId();

    if (assignedChannel < 1 || assignedChannel > 0xFF) {
      throw RangeError.range(assignedChannel, 1, 0xFF, 'channelId');
    }
    if (_servicesByChannel.containsKey(assignedChannel)) {
      throw StateError('Channel $assignedChannel is already registered.');
    }

    _servicesByChannel[assignedChannel] = RegisteredService(
      name: name,
      channelId: assignedChannel,
      buildDescriptor: buildDescriptor,
    );
    _channelsByName[name] = assignedChannel;

    _log.info('Registered service "$name" on channel $assignedChannel.');
    return assignedChannel;
  }

  bool unregisterService(String name) {
    _checkNotDisposed();

    final channelId = _channelsByName.remove(name);
    if (channelId == null) return false;

    _servicesByChannel.remove(channelId);
    return true;
  }

  RegisteredService? serviceForChannel(int channelId) =>
      _servicesByChannel[channelId];

  RegisteredService? serviceNamed(String name) {
    final id = _channelsByName[name];
    return id == null ? null : _servicesByChannel[id];
  }

  List<ChannelDescriptor> buildLocalDescriptors() {
    _checkNotDisposed();

    return List.unmodifiable(
      _servicesByChannel.values.map((service) {
        final descriptor = service.buildDescriptor(service.channelId);
        descriptor.channelId = service.channelId;
        return descriptor;
      }).toList(),
    );
  }

  /// Start listening for the phone's 0x0005 before sending our 0x0006.
  void start() {
    _checkNotDisposed();
    if (_started) return;

    _started = true;
    _requestCompleter = Completer<ServiceDiscoveryRequest>();

    _subscription = _router
        .forMessageId(serviceDiscoveryRequestId, channel: controlChannel)
        .listen(
          (dynamic message) {
            unawaited(_handleDiscoveryRequest(message));
          },
          onError: (Object error, StackTrace stackTrace) {
            _log.severe(
              'Service discovery request stream failed.',
              error,
              stackTrace,
            );

            final completer = _requestCompleter;
            if (completer != null && !completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        );

    _log.info('Listening for phone service discovery request (0x0005).');
  }

  /// Send the HU's SERVICE_DISCOVERY_RESPONSE (0x0006) first.
  ///
  /// Call after TLS is established and AUTH_COMPLETE has been sent.
  Future<ServiceDiscoveryResponse> discover() async {
    _checkNotDisposed();

    if (_discoveryCompleted) {
      throw StateError('Service discovery response has already been sent.');
    }

    // Subscribe before sending, so a fast phone response is not missed.
    start();

    final response = ServiceDiscoveryResponse(
      channels: buildLocalDescriptors(),

      // Head-unit identity
      headUnitName: 'FlutterAuto',
      carModel: 'Android Auto Emulator',
      carYear: '2026',
      carSerial: 'FLUTTERAUTO-001',
      driverPosition: DriverPosition_Enum.LEFT,
      headunitManufacturer: 'FlutterAuto',
      headunitModel: 'FlutterAuto',
      swBuild: 'flutter-auto-dev',
      swVersion: '1.0.0',

      // Capabilities
      canPlayNativeMediaDuringVr: false,
      sessionConfiguration: 0,
      displayName: 'FlutterAuto',
      probeForSupport: false,
    );

    final responseBytes = response.writeToBuffer();
    final payload = Uint8List(2 + responseBytes.length);

    ByteData.sublistView(
      payload,
    ).setUint16(0, serviceDiscoveryResponseId, Endian.big);
    payload.setRange(2, payload.length, responseBytes);

    String hex(List<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

    _log.info('========== Service Discovery Response ==========');
    _log.info(
      'Message ID: 0x${serviceDiscoveryResponseId.toRadixString(16).padLeft(4, '0')}',
    );
    _log.info('Channel count: ${response.channels.length}');

    for (final channel in response.channels) {
      _log.info('Channel descriptor: $channel');
    }

    _log.info('Protobuf JSON: ${response.toProto3Json()}');
    _log.info('Protobuf length: ${responseBytes.length} bytes');
    _log.info('Protobuf hex: ${hex(responseBytes)}');
    _log.info('Full payload length: ${payload.length} bytes');
    _log.info('Full payload hex: ${hex(payload)}');
    _log.info('================================================');

    await _sendControlPayload(payload);

    // Only mark discovery complete after the send succeeds.
    localDiscoveryResponse = response;
    _discoveryCompleted = true;

    _log.info(
      'Sent SERVICE_DISCOVERY_RESPONSE (0x0006) with '
      '${response.channels.length} channel descriptors.',
    );

    return response;
  }

  /// Wait for the phone's subsequent SERVICE_DISCOVERY_REQUEST (0x0005).
  Future<ServiceDiscoveryRequest> waitForPhoneRequest({
    Duration timeout = const Duration(seconds: 15),
  }) {
    _checkNotDisposed();
    start();

    return _requestCompleter!.future.timeout(timeout);
  }

  Future<void> _handleDiscoveryRequest(dynamic message) async {
    if (_disposed || _requestReceived) return;

    try {
      final List<int> raw = List<int>.from(message.payload as List<int>);

      // MessageRouter may provide either the full logical payload (ID + body)
      // or only the protobuf body.
      final List<int> body;
      if (raw.length >= 2 &&
          raw[0] == 0x00 &&
          raw[1] == serviceDiscoveryRequestId) {
        body = raw.sublist(2);
      } else {
        body = raw;
      }

      final request = ServiceDiscoveryRequest.fromBuffer(body);

      phoneRequest = request;
      _requestReceived = true;

      _log.info(
        'Received SERVICE_DISCOVERY_REQUEST (0x0005): '
        'device_name="${request.deviceName}", '
        'device_brand="${request.deviceBrand}".',
      );

      final completer = _requestCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(request);
      }

      // Do not send 0x0006 here: it was already sent by discover().
    } catch (error, stackTrace) {
      _log.severe(
        'Failed to parse service discovery request.',
        error,
        stackTrace,
      );

      final completer = _requestCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }

  int _allocateChannelId() {
    for (int id = 1; id <= 0xFF; id++) {
      if (!_servicesByChannel.containsKey(id)) return id;
    }
    throw StateError('No available channel IDs remain.');
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('ServiceManager has been disposed.');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _subscription?.cancel();

    final completer = _requestCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        StateError('ServiceManager disposed before the phone request arrived.'),
      );
    }

    _servicesByChannel.clear();
    _channelsByName.clear();
    _started = false;

    _log.info('ServiceManager disposed.');
  }
}
