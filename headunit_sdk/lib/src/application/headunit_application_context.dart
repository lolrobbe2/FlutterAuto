import 'package:headunit_contracts/headunit_contracts.dart';

import '../connection/headunit_connection.dart';

class HeadunitApplicationContext {
  final ApplicationId applicationId;
  final ServiceBroker? _localServices;
  final HeadunitConnection? connection;

  final String? locale;
  final String? productId;

  const HeadunitApplicationContext({
    required this.applicationId,
    ServiceBroker? services,
    this.connection,
    this.locale,
    this.productId,
  }) : _localServices = services,
       assert(services != null || connection != null),
       assert(services == null || connection == null);

  factory HeadunitApplicationContext.fromConnection(
    HeadunitConnection connection,
  ) {
    return HeadunitApplicationContext(
      applicationId: connection.applicationId,
      connection: connection,
      locale: connection.locale,
      productId: connection.productId,
    );
  }

  /// In-process ServiceBroker. External applications should use
  /// [remoteServices] instead because Dart objects cannot cross process
  /// boundaries.
  ServiceBroker get services {
    final ServiceBroker? broker = _localServices;
    if (broker == null) {
      throw StateError(
        'In-process services are unavailable to an external application. '
        'Use remoteServices.acquire instead.',
      );
    }
    return broker;
  }

  HeadunitServiceClient get remoteServices {
    final HeadunitConnection? remoteConnection = connection;
    if (remoteConnection == null) {
      throw StateError(
        'Remote services are only available to an external application.',
      );
    }
    return remoteConnection.services;
  }

  bool hasCapability(CapabilityId capability) {
    final ServiceBroker? localServices = _localServices;
    if (localServices != null) {
      return localServices.hasCapability(capability);
    }
    return connection?.hasCapability(capability) ?? false;
  }

  T getService<T extends Object>(ServiceKey<T> key) {
    return services.getService(key);
  }

  Future<T> acquireService<T extends Object>(RemoteServiceKey<T> key) {
    return remoteServices.acquire(key);
  }
}
