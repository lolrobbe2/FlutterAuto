import 'dart:async';

import 'package:headunit_shared/headunit_shared_io.dart';

/// Authenticated connection from an external application to its headunit.
///
/// Use this instead of depending on runtime implementation classes. The
/// connection carries small control/service RPC messages only; media streams
/// use a separate native transport.
class HeadunitConnection {
  final RpcConnection _rpc;
  final ApplicationId applicationId;
  final List<CapabilityId> grantedCapabilities;
  final String? locale;
  final String? productId;
  final int? _mediaPort;
  final String _host;
  final String _token;
  MediaStreamClient? _mediaClient;
  Future<MediaStreamClient>? _mediaOpening;

  late final HeadunitServiceClient services = HeadunitServiceClient(_rpc);

  HeadunitConnection._({
    required this._rpc,
    required this.applicationId,
    required List<CapabilityId> grantedCapabilities,
    required this.locale,
    required this.productId,
    required this._mediaPort,
    required this._host,
    required this._token,
  }) : grantedCapabilities = List<CapabilityId>.unmodifiable(
         grantedCapabilities,
       );

  static Future<HeadunitConnection> connect({
    required int port,
    required String token,
    String host = '127.0.0.1',
    int? mediaPort,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (host != '127.0.0.1') {
      throw ArgumentError.value(
        host,
        'host',
        'Headunit IPC is restricted to IPv4 loopback.',
      );
    }
    if (mediaPort != null && (mediaPort < 1 || mediaPort > 65535)) {
      throw ArgumentError.value(mediaPort, 'mediaPort');
    }
    final RpcConnection rpc = await RpcConnection.connect(
      host: host,
      port: port,
      timeout: timeout,
    );

    try {
      final Object? rawResult = await rpc.request(
        'session.authenticate',
        parameters: <String, Object?>{'token': token},
        timeout: timeout,
      );
      final Map<String, Object?> result = _toStringMap(rawResult);
      final Object? rawApplicationId = result['applicationId'];
      final Object? rawCapabilities = result['grantedCapabilities'];

      if (rawApplicationId is! String || rawCapabilities is! List) {
        throw const FormatException('Invalid headunit session response.');
      }

      final List<CapabilityId> capabilities = <CapabilityId>[];
      for (final Object? value in rawCapabilities) {
        if (value is! String) {
          throw const FormatException('Invalid granted capability.');
        }
        capabilities.add(CapabilityId(value));
      }

      final Object? rawLocale = result['locale'];
      final Object? rawProductId = result['productId'];
      if (rawLocale != null && rawLocale is! String) {
        throw const FormatException('Invalid application locale.');
      }
      if (rawProductId != null && rawProductId is! String) {
        throw const FormatException('Invalid product identifier.');
      }

      return HeadunitConnection._(
        rpc: rpc,
        applicationId: ApplicationId(rawApplicationId),
        grantedCapabilities: capabilities,
        locale: rawLocale as String?,
        productId: rawProductId as String?,
        mediaPort: mediaPort,
        host: host,
        token: token,
      );
    } catch (_) {
      await rpc.close();
      rethrow;
    }
  }

  bool hasCapability(CapabilityId capability) {
    return grantedCapabilities.contains(capability);
  }

  Stream<HeadunitHostEvent> get notifications => _rpc.notifications.map(
    (RpcNotification notification) => HeadunitHostEvent(
      method: notification.method,
      parameters: notification.parameters,
    ),
  );

  Stream<RemoteServiceEvent> get serviceEvents => services.events;

  Stream<ApplicationPointerEvent> get pointerEvents => notifications
      .where((HeadunitHostEvent event) => event.method == 'input.pointer')
      .map(
        (HeadunitHostEvent event) =>
            ApplicationPointerEvent.fromJson(event.parameters),
      );

  bool get isConnected => !_rpc.isClosed;

  /// Opens the compressed-video channel supplied by the host launcher.
  /// The host selects codec, resolution, frame rate and target bitrate.
  Future<MediaStreamClient> openMediaStream({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!isConnected) {
      throw StateError('Headunit control connection is closed.');
    }
    final int? mediaPort = _mediaPort;
    if (mediaPort == null) {
      throw StateError('No media endpoint was supplied by the launcher.');
    }
    final MediaStreamClient? existing = _mediaClient;
    if (existing != null && !existing.isClosed) {
      return existing;
    }
    final Future<MediaStreamClient>? pending = _mediaOpening;
    if (pending != null) {
      return pending;
    }

    final Future<MediaStreamClient> opening = MediaStreamClient.connect(
      host: _host,
      port: mediaPort,
      token: _token,
      timeout: timeout,
    );
    _mediaOpening = opening;
    try {
      final MediaStreamClient client = await opening;
      _mediaClient = client;
      return client;
    } finally {
      if (identical(_mediaOpening, opening)) {
        _mediaOpening = null;
      }
    }
  }

  Future<void> close() async {
    try {
      final Future<MediaStreamClient>? opening = _mediaOpening;
      if (opening != null) {
        try {
          final MediaStreamClient client = await opening;
          await client.close();
        } catch (_) {
          // The media handshake may fail while the control channel shuts down.
        }
        _mediaOpening = null;
        _mediaClient = null;
      } else {
        final MediaStreamClient? client = _mediaClient;
        _mediaClient = null;
        await client?.close();
      }
    } finally {
      await _rpc.close();
    }
  }

  static Map<String, Object?> _toStringMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Expected a JSON object.');
    }

    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('JSON object keys must be strings.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
}

/// A small control-plane event published by the headunit.
///
/// Event parameters are JSON-compatible values. Media payloads never travel
/// through this event stream.
class HeadunitHostEvent {
  final String method;
  final Map<String, Object?> parameters;

  HeadunitHostEvent({
    required this.method,
    required Map<String, Object?> parameters,
  }) : parameters = Map<String, Object?>.unmodifiable(parameters);
}

/// Resolves remote service access through the authenticated application
/// connection. The host repeats capability checks for every invocation.
class HeadunitServiceClient {
  final RpcConnection _rpc;
  final Map<ServiceId, RemoteServiceHandle> _handles =
      <ServiceId, RemoteServiceHandle>{};
  final Map<ServiceId, Future<RemoteServiceHandle>> _pendingAcquisitions =
      <ServiceId, Future<RemoteServiceHandle>>{};
  final StreamController<RemoteServiceEvent> _events =
      StreamController<RemoteServiceEvent>.broadcast(sync: true);

  HeadunitServiceClient(this._rpc) {
    _rpc.notifications.listen(
      _handleNotification,
      onDone: () {
        if (!_events.isClosed) {
          unawaited(_events.close());
        }
      },
    );
  }

  Stream<RemoteServiceEvent> get events => _events.stream;

  void _handleNotification(RpcNotification notification) {
    if (notification.method != 'service.event') {
      return;
    }
    final Object? rawServiceId = notification.parameters['serviceId'];
    final Object? rawEvent = notification.parameters['event'];
    final Object? rawData = notification.parameters['data'];
    if (rawServiceId is! String || rawEvent is! String || rawData is! Map) {
      return;
    }

    final Map<String, Object?> data = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in rawData.entries) {
      if (entry.key is! String) {
        return;
      }
      data[entry.key as String] = entry.value;
    }

    try {
      _events.add(
        RemoteServiceEvent(
          serviceId: ServiceId(rawServiceId),
          event: rawEvent,
          data: data,
        ),
      );
    } on ArgumentError {
      // Ignore malformed service events. The transport itself remains valid.
    }
  }

  Future<T> acquire<T extends Object>(RemoteServiceKey<T> key) async {
    final RemoteServiceHandle handle = await acquireHandle(key.serviceId);
    return key.create(handle);
  }

  Future<RemoteServiceHandle> acquireHandle(ServiceId serviceId) async {
    final RemoteServiceHandle? existing = _handles[serviceId];
    if (existing != null) {
      return existing;
    }

    final Future<RemoteServiceHandle>? pending =
        _pendingAcquisitions[serviceId];
    if (pending != null) {
      return pending;
    }

    final Future<RemoteServiceHandle> acquisition =
        _acquireHandleInternal(serviceId);
    _pendingAcquisitions[serviceId] = acquisition;
    try {
      return await acquisition;
    } finally {
      if (identical(_pendingAcquisitions[serviceId], acquisition)) {
        _pendingAcquisitions.remove(serviceId);
      }
    }
  }

  Future<RemoteServiceHandle> _acquireHandleInternal(
    ServiceId serviceId,
  ) async {
    final Object? rawResult = await _rpc.request(
      'service.acquire',
      parameters: <String, Object?>{'serviceId': serviceId.value},
    );
    final Map<String, Object?> result = HeadunitConnection._toStringMap(
      rawResult,
    );
    final Object? rawMethods = result['methods'];
    if (result['serviceId'] != serviceId.value || rawMethods is! List) {
      throw const FormatException('Invalid remote service descriptor.');
    }

    final Set<String> methods = <String>{};
    for (final Object? method in rawMethods) {
      if (method is! String || method.isEmpty) {
        throw const FormatException('Invalid remote service method.');
      }
      methods.add(method);
    }

    final RemoteServiceHandle handle = RemoteServiceHandle._(
      client: this,
      rpc: _rpc,
      serviceId: serviceId,
      methods: methods,
    );
    _handles[serviceId] = handle;
    return handle;
  }
}

/// Typed SDK key for a remote service. Service implementations provide a
/// small client wrapper around [RemoteServiceHandle] instead of exposing raw
/// transport calls to application code.
final class RemoteServiceKey<T extends Object> {
  final ServiceId serviceId;
  final T Function(RemoteServiceHandle handle) create;

  const RemoteServiceKey({
    required this.serviceId,
    required this.create,
  });
}

class RemoteServiceEvent {
  final ServiceId serviceId;
  final String event;
  final Map<String, Object?> data;

  RemoteServiceEvent({
    required this.serviceId,
    required this.event,
    required Map<String, Object?> data,
  }) : data = Map<String, Object?>.unmodifiable(data);
}

/// An allow-listed remote service acquired from the headunit SDK.
class RemoteServiceHandle {
  final HeadunitServiceClient _client;
  final RpcConnection _rpc;
  final ServiceId serviceId;
  final Set<String> methods;
  bool _eventsSubscribed = false;

  RemoteServiceHandle._({
    required this._client,
    required this._rpc,
    required this.serviceId,
    required Set<String> methods,
  }) : methods = Set<String>.unmodifiable(methods);

  Stream<RemoteServiceEvent> get events => _client.events.where(
    (RemoteServiceEvent event) => event.serviceId == serviceId,
  );

  Future<void> subscribeEvents({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_eventsSubscribed) {
      return;
    }
    await _rpc.request(
      'service.subscribe',
      parameters: <String, Object?>{'serviceId': serviceId.value},
      timeout: timeout,
    );
    _eventsSubscribed = true;
  }

  Future<void> unsubscribeEvents({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!_eventsSubscribed) {
      return;
    }
    await _rpc.request(
      'service.unsubscribe',
      parameters: <String, Object?>{'serviceId': serviceId.value},
      timeout: timeout,
    );
    _eventsSubscribed = false;
  }

  Future<Object?> invoke(
    String method, {
    Map<String, Object?> arguments = const <String, Object?>{},
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (!methods.contains(method)) {
      throw ArgumentError.value(
        method,
        'method',
        'Method is not exposed by ${serviceId.value}.',
      );
    }

    return _rpc.request(
      'service.invoke',
      parameters: <String, Object?>{
        'serviceId': serviceId.value,
        'method': method,
        'arguments': arguments,
      },
      timeout: timeout,
    );
  }
}
