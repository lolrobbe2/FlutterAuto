import 'package:headunit_contracts/headunit_contracts.dart';

class HeadunitApplicationContext {
  final ApplicationId applicationId;
  final ServiceBroker services;

  final String? locale;
  final String? productId;

  const HeadunitApplicationContext({
    required this.applicationId,
    required this.services,
    this.locale,
    this.productId,
  });

  bool hasCapability(CapabilityId capability) {
    return services.hasCapability(capability);
  }

  T getService<T extends Object>(ServiceKey<T> key) {
    return services.getService(key);
  }
}