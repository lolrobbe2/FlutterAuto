import '../capabilities/capability_id.dart';
import 'service_broker.dart';
import 'service_id.dart';

/// Optional RPC surface implemented by the runtime's [ServiceBroker].
///
/// In-process applications continue to use [ServiceBroker.getService].
/// External applications use these serializable operations over IPC.
abstract interface class RemoteServiceBroker implements ServiceBroker {
  /// Exact capability grant set used to construct this broker.
  List<CapabilityId> get grantedCapabilities;

  List<String> getRemoteMethods(ServiceId serviceId);

  Future<Object?> invokeRemote({
    required ServiceId serviceId,
    required String method,
    Map<String, Object?> arguments = const <String, Object?>{},
  });
}
