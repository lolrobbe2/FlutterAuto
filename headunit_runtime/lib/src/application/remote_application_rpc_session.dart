import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:headunit_shared/headunit_shared_io.dart';

import '../services/remote_service_adapter.dart';

import 'remote_application_ui_channel.dart';

/// Connection details a platform launcher passes to the external application.
/// The token is single-session and must be delivered through the platform's
/// protected process-bootstrap mechanism.
class RemoteApplicationEndpoint {
  final String host;
  final int port;
  final int mediaPort;
  final String token;

  const RemoteApplicationEndpoint({
    required this.host,
    required this.port,
    required this.mediaPort,
    required this.token,
  });
}

/// Owns the host side of one external application's RPC connection.
///
/// It does not launch a process or encode/decode video. Platform launchers
/// pass [endpoint] to the child; the child uses the SDK control connection and
/// the separate compressed-media connection. The session exposes only the
/// capabilities in [context].
class RemoteApplicationRpcSession {
  final ApplicationLaunchContext _context;
  final RemoteServiceBroker _serviceBroker;
  final LocalRpcServer _server;
  final LocalMediaServer _mediaServer;
  final String _token;
  final Completer<void> _authenticationCompleter = Completer<void>();
  final Set<ServiceId> _eventSubscriptions = <ServiceId>{};
  final RemoteApplicationUiChannel uiChannel = RemoteApplicationUiChannel();

  StreamSubscription<RpcConnection>? _connectionSubscription;
  RpcConnection? _connection;
  Timer? _authenticationTimer;
  bool _authenticated = false;
  bool _disposed = false;

  RemoteApplicationRpcSession._({
    required this._context,
    required this._serviceBroker,
    required this._server,
    required this._mediaServer,
    required this._token,
  }) {
    _connectionSubscription = _server.connections.listen(_attachConnection);
  }

  static Future<RemoteApplicationRpcSession> bind({
    required ApplicationLaunchContext context,
    required RemoteServiceBroker serviceBroker,
    VideoStreamConfiguration mediaConfiguration =
        VideoStreamConfiguration.defaultConfiguration,
  }) async {
    if (serviceBroker.applicationId != context.applicationId) {
      throw ArgumentError(
        'Service broker identity does not match the application session.',
      );
    }
    final Set<String> contextCapabilities = context.grantedCapabilities
        .map((CapabilityId capability) => capability.value)
        .toSet();
    final Set<String> brokerCapabilities = serviceBroker.grantedCapabilities
        .map((CapabilityId capability) => capability.value)
        .toSet();
    if (contextCapabilities.length != brokerCapabilities.length ||
        !contextCapabilities.containsAll(brokerCapabilities)) {
      throw ArgumentError(
        'Service broker capabilities do not match the application session.',
      );
    }
    final String token = _createToken();
    final LocalRpcServer server = await LocalRpcServer.bind(maxConnections: 1);
    try {
      final LocalMediaServer mediaServer = await LocalMediaServer.bind(
        token: token,
        configuration: mediaConfiguration,
        maxConnections: 1,
        maxQueuedFrames: 2,
      );
      return RemoteApplicationRpcSession._(
        context: context,
        serviceBroker: serviceBroker,
        server: server,
        mediaServer: mediaServer,
        token: token,
      );
    } catch (_) {
      await server.close();
      rethrow;
    }
  }

  RemoteApplicationEndpoint get endpoint {
    _ensureActive();
    return RemoteApplicationEndpoint(
      host: _server.host,
      port: _server.port,
      mediaPort: _mediaServer.port,
      token: _token,
    );
  }

  bool get isConnected => _connection != null && !_connection!.isClosed;
  bool get isAuthenticated => _authenticated;

  /// Host-side compressed video connections for this application session.
  /// Subscribe before launching the child process.
  Stream<MediaStreamConnection> get mediaConnections =>
      _mediaServer.connections;
  Future<void> waitUntilAuthenticated({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _ensureActive();
    if (_authenticated) {
      return;
    }
    await _authenticationCompleter.future.timeout(timeout);
  }

  void _attachConnection(RpcConnection connection) {
    final RpcConnection? existing = _connection;
    if (_disposed || (existing != null && !existing.isClosed)) {
      unawaited(connection.close());
      return;
    }

    _connection = connection;
    _authenticated = false;
    _eventSubscriptions.clear();
    _authenticationTimer?.cancel();
    _authenticationTimer = Timer(const Duration(seconds: 10), () {
      if (!_disposed && identical(_connection, connection) && !_authenticated) {
        unawaited(connection.close());
      }
    });
    unawaited(
      connection.done.whenComplete(() {
        if (identical(_connection, connection)) {
          _authenticationTimer?.cancel();
          _authenticationTimer = null;
          _connection = null;
          if (!_disposed) {
            _authenticated = false;
          }
        }
      }),
    );
    connection.registerRequestHandler('session.authenticate', _authenticate);
    connection.registerRequestHandler('service.acquire', _acquireService);
    connection.registerRequestHandler('service.invoke', _invokeService);
    connection.registerRequestHandler('service.subscribe', _subscribeService);
    connection.registerRequestHandler(
      'service.unsubscribe',
      _unsubscribeService,
    );
    uiChannel.attach(connection, isAuthenticated: () => _authenticated);
  }

  Future<Object?> _authenticate(Map<String, Object?> parameters) async {
    if (_authenticated) {
      throw const RpcException(-32001, 'Session is already authenticated.');
    }

    final Object? suppliedToken = parameters['token'];
    if (suppliedToken is! String ||
        !_constantTimeEquals(suppliedToken, _token)) {
      throw const RpcException(-32001, 'Invalid application session token.');
    }

    _authenticationTimer?.cancel();
    _authenticationTimer = null;
    _authenticated = true;
    if (!_authenticationCompleter.isCompleted) {
      _authenticationCompleter.complete();
    }
    return <String, Object?>{
      'applicationId': _context.applicationId.value,
      'grantedCapabilities': _context.grantedCapabilities
          .map((CapabilityId capability) => capability.value)
          .toList(growable: false),
      'locale': _context.locale,
      'productId': _context.productId,
    };
  }

  Future<Object?> _acquireService(Map<String, Object?> parameters) async {
    _ensureAuthenticated();
    final ServiceId serviceId = _readServiceId(parameters);

    try {
      final List<String> methods = _serviceBroker.getRemoteMethods(serviceId);
      return <String, Object?>{
        'serviceId': serviceId.value,
        'methods': methods,
      };
    } on ServiceAccessDeniedException catch (error) {
      throw RpcException(-32003, error.toString());
    } on ServiceNotFoundException catch (error) {
      throw RpcException(-32004, error.toString());
    }
  }

  Future<Object?> _subscribeService(Map<String, Object?> parameters) async {
    _ensureAuthenticated();
    final ServiceId serviceId = _readServiceId(parameters);
    try {
      _serviceBroker.getRemoteMethods(serviceId);
      _eventSubscriptions.add(serviceId);
      return <String, Object?>{'subscribed': true};
    } on ServiceAccessDeniedException catch (error) {
      throw RpcException(-32003, error.toString());
    } on ServiceNotFoundException catch (error) {
      throw RpcException(-32004, error.toString());
    }
  }

  Future<Object?> _unsubscribeService(Map<String, Object?> parameters) async {
    _ensureAuthenticated();
    final ServiceId serviceId = _readServiceId(parameters);
    _eventSubscriptions.remove(serviceId);
    return <String, Object?>{'subscribed': false};
  }

  Future<Object?> _invokeService(Map<String, Object?> parameters) async {
    _ensureAuthenticated();
    final ServiceId serviceId = _readServiceId(parameters);
    final Object? rawMethod = parameters['method'];
    if (rawMethod is! String || rawMethod.isEmpty || rawMethod.length > 128) {
      throw const RpcException(-32602, 'Invalid service method.');
    }
    final Object rawArguments =
        parameters['arguments'] ?? const <String, Object?>{};
    if (rawArguments is! Map) {
      throw const RpcException(-32602, 'Service arguments must be an object.');
    }

    final Map<String, Object?> arguments = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in rawArguments.entries) {
      if (entry.key is! String) {
        throw const RpcException(
          -32602,
          'Service argument keys must be strings.',
        );
      }
      arguments[entry.key as String] = entry.value;
    }

    try {
      return await _serviceBroker.invokeRemote(
        serviceId: serviceId,
        method: rawMethod,
        arguments: arguments,
      );
    } on ServiceAccessDeniedException catch (error) {
      throw RpcException(-32003, error.toString());
    } on ServiceNotFoundException catch (error) {
      throw RpcException(-32004, error.toString());
    } on RemoteServiceMethodNotFoundException catch (error) {
      throw RpcException(-32601, error.toString());
    }
  }

  void sendLifecycleState(ApplicationLifecycleState state) {
    _sendNotification('application.lifecycle', <String, Object?>{
      'state': state.name,
    });
  }

  /// Publishes a typed service event to the external application.
  ///
  /// The host revalidates that the application has access to the service
  /// before publishing. Event payloads must be JSON-compatible and small.
  void publishServiceEvent({
    required ServiceId serviceId,
    required String event,
    required Map<String, Object?> data,
  }) {
    if (event.trim().isEmpty || event.length > 128) {
      throw ArgumentError.value(event, 'event');
    }
    if (!_authenticated ||
        _connection == null ||
        _connection!.isClosed ||
        !_eventSubscriptions.contains(serviceId)) {
      return;
    }
    try {
      _serviceBroker.getRemoteMethods(serviceId);
    } on ServiceAccessDeniedException {
      return;
    } on ServiceNotFoundException {
      return;
    }
    _sendNotification('service.event', <String, Object?>{
      'serviceId': serviceId.value,
      'event': event,
      'data': data,
    });
  }

  /// Sends a normalized multitouch event to the external application.
  void sendPointerEvent(ApplicationPointerEvent event) {
    _sendNotification('input.pointer', event.toJson());
  }

  /// Sends an action invocation to the currently published UI page.
  void sendUiAction(String actionId) {
    uiChannel.sendAction(actionId);
  }

  /// Sends a low-volume, application-specific input event.
  ///
  /// This channel is for control input, not media frames.
  void sendInputEvent(
    String eventType, {
    required Map<String, Object?> parameters,
  }) {
    if (eventType.trim().isEmpty || eventType.length > 64) {
      throw ArgumentError.value(eventType, 'eventType');
    }
    _sendNotification('input.$eventType', parameters);
  }

  void _sendNotification(String method, Map<String, Object?> parameters) {
    if (!_authenticated || _connection == null || _connection!.isClosed) {
      return;
    }
    _connection!.notify(method, parameters: parameters);
  }

  ServiceId _readServiceId(Map<String, Object?> parameters) {
    final Object? value = parameters['serviceId'];
    if (value is! String) {
      throw const RpcException(-32602, 'Missing serviceId.');
    }
    try {
      return ServiceId(value);
    } on ArgumentError {
      throw const RpcException(-32602, 'Invalid serviceId.');
    }
  }

  void _ensureAuthenticated() {
    if (!_authenticated) {
      throw const RpcException(
        -32001,
        'Application session is not authenticated.',
      );
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('Remote application RPC session is disposed.');
    }
  }

  static String _createToken() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(
      32,
      (_) => random.nextInt(256),
      growable: false,
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) {
      return false;
    }
    int difference = 0;
    for (int index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _authenticationTimer?.cancel();
    _authenticationTimer = null;
    _eventSubscriptions.clear();
    await _connectionSubscription?.cancel();
    await uiChannel.dispose();
    await _server.close();
    await _mediaServer.close();
    _connection = null;
  }
}
