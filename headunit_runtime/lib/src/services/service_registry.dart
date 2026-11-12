import 'package:headunit_contracts/headunit_contracts.dart';

class ServiceRegistry {
  final Map<ServiceId, _RegisteredService> _services = {};

  bool _disposed = false;

  void register<T extends Object>({
    required ServiceKey<T> key,
    required T instance,
    Iterable<CapabilityId> requiredCapabilities = const [],
  }) {
    _ensureActive();

    if (_services.containsKey(key.id)) {
      throw StateError(
        'Service ${key.id} is already registered.',
      );
    }

    _services[key.id] = _RegisteredService(
      instance: instance,
      requiredCapabilities: requiredCapabilities,
    );
  }

  bool unregister(ServiceId id) {
    _ensureActive();

    return _services.remove(id) != null;
  }

  ServiceBroker createBroker(ApplicationLaunchContext context) {
    _ensureActive();

    return _RuntimeServiceBroker(
      registry: this,
      context: context,
    );
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

    final List<CapabilityId> missingCapabilities =
        registration.requiredCapabilities
            .where(
              (CapabilityId capability) =>
                  !context.hasCapability(capability),
            )
            .toList();

    if (missingCapabilities.isNotEmpty) {
      throw ServiceAccessDeniedException(
        applicationId: context.applicationId,
        serviceId: key.id,
        missingCapabilities: missingCapabilities,
      );
    }

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

  void dispose() {
    if (_disposed) {
      return;
    }

    _services.clear();
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
  }) : requiredCapabilities =
           Set<CapabilityId>.unmodifiable(requiredCapabilities);
}

class _RuntimeServiceBroker implements ServiceBroker {
  final ServiceRegistry _registry;
  final ApplicationLaunchContext _context;

  _RuntimeServiceBroker({
    required this._registry,
    required this._context,
  });

  @override
  ApplicationId get applicationId => _context.applicationId;

  @override
  T getService<T extends Object>(ServiceKey<T> key) {
    return _registry._resolve(
      context: _context,
      key: key,
    );
  }

  @override
  bool hasCapability(CapabilityId capability) {
    return _context.hasCapability(capability);
  }
}