import 'package:headunit_shared/headunit_shared_io.dart';

import 'remote_service_adapter.dart';

class ServiceRegistry {
  final Map<ServiceId, _RegisteredService> _services = {};
  final Map<ServiceId, RemoteServiceAdapter> _remoteServices = {};

  bool _disposed = false;

  void register<T extends Object>({
    required ServiceKey<T> key,
    required T instance,
    Iterable<CapabilityId> requiredCapabilities = const [],
  }) {
    _ensureActive();

    if (_services.containsKey(key.id)) {
      throw StateError('Service ${key.id} is already registered.');
    }
    _services[key.id] = _RegisteredService(
      instance: instance,
      requiredCapabilities: requiredCapabilities,
    );
  }

  /// Registers the serializable API exposed to applications in another
  /// process. A service may have both an in-process implementation and a
  /// remote adapter under the same [ServiceId].
  void registerRemoteService(RemoteServiceAdapter adapter) {
    _ensureActive();
    if (_remoteServices.containsKey(adapter.serviceId)) {
      throw StateError(
        'Remote service ${adapter.serviceId} is already registered.',
      );
    }
    _remoteServices[adapter.serviceId] = adapter;
  }

  bool unregister(ServiceId id) {
    _ensureActive();
    final bool localRemoved = _services.remove(id) != null;
    final bool remoteRemoved = _remoteServices.remove(id) != null;
    return localRemoved || remoteRemoved;
  }

  RemoteServiceBroker createBroker(ApplicationLaunchContext context) {
    _ensureActive();
    return _RuntimeServiceBroker(registry: this, context: context);
  }

  T _resolve<T extends Object>({
    required ApplicationLaunchContext context,
    required ServiceKey<T> key,
  }) {
    _ensureActive();

    final _RegisteredService? registration = _services[key.id];
    if (registration == null) {
      throw ServiceNotFoundException(key.id.value);
    }

    _checkCapabilities(
      applicationId: context.applicationId,
      serviceId: key.id,
      requiredCapabilities: registration.requiredCapabilities,
      context: context,
    );

    final Object instance = registration.instance;
    if (instance is! T) {
      throw ServiceTypeMismatchException(
        serviceId: key.id,
        expectedType: T.toString(),
        actualType: instance.runtimeType.toString(),
      );
    }

    return instance;
  }

  List<String> _getRemoteMethods({
    required ApplicationLaunchContext context,
    required ServiceId serviceId,
  }) {
    _ensureActive();
    final RemoteServiceAdapter? adapter = _remoteServices[serviceId];
    if (adapter == null) {
      throw ServiceNotFoundException(serviceId.value);
    }

    _checkCapabilities(
      applicationId: context.applicationId,
      serviceId: serviceId,
      requiredCapabilities: adapter.requiredCapabilities,
      context: context,
    );
    return adapter.methods;
  }

  Future<Object?> _invokeRemote({
    required ApplicationLaunchContext context,
    required ServiceId serviceId,
    required String method,
    required Map<String, Object?> arguments,
  }) async {
    _ensureActive();
    final RemoteServiceAdapter? adapter = _remoteServices[serviceId];
    if (adapter == null) {
      throw ServiceNotFoundException(serviceId.value);
    }

    _checkCapabilities(
      applicationId: context.applicationId,
      serviceId: serviceId,
      requiredCapabilities: adapter.requiredCapabilities,
      context: context,
    );
    return adapter.invoke(method, arguments);
  }

  void _checkCapabilities({
    required ApplicationId applicationId,
    required ServiceId serviceId,
    required Iterable<CapabilityId> requiredCapabilities,
    required ApplicationLaunchContext context,
  }) {
    final List<CapabilityId> missingCapabilities = requiredCapabilities
        .where((CapabilityId capability) => !context.hasCapability(capability))
        .toList(growable: false);

    if (missingCapabilities.isNotEmpty) {
      throw ServiceAccessDeniedException(
        applicationId: applicationId,
        serviceId: serviceId,
        missingCapabilities: missingCapabilities,
      );
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _services.clear();
    _remoteServices.clear();
    _disposed = true;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('ServiceRegistry has been disposed.');
    }
  }
}

class _RegisteredService {
  final Object instance;
  final Set<CapabilityId> requiredCapabilities;

  _RegisteredService({
    required this.instance,
    required Iterable<CapabilityId> requiredCapabilities,
  }) : requiredCapabilities = Set<CapabilityId>.unmodifiable(
         requiredCapabilities,
       );
}

class _RuntimeServiceBroker implements RemoteServiceBroker {
  final ServiceRegistry _registry;
  final ApplicationLaunchContext _context;

  _RuntimeServiceBroker({required this._registry, required this._context});

  @override
  ApplicationId get applicationId => _context.applicationId;

  @override
  List<CapabilityId> get grantedCapabilities => _context.grantedCapabilities;

  @override
  T getService<T extends Object>(ServiceKey<T> key) {
    return _registry._resolve(context: _context, key: key);
  }

  @override
  bool hasCapability(CapabilityId capability) {
    return _context.hasCapability(capability);
  }

  @override
  List<String> getRemoteMethods(ServiceId serviceId) {
    return _registry._getRemoteMethods(context: _context, serviceId: serviceId);
  }

  @override
  Future<Object?> invokeRemote({
    required ServiceId serviceId,
    required String method,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) {
    return _registry._invokeRemote(
      context: _context,
      serviceId: serviceId,
      method: method,
      arguments: arguments,
    );
  }
}
