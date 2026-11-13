import 'package:headunit_sdk/headunit_sdk.dart';

/// Tiny JSON-RPC service used by the external-process demo to prove that the
/// child acquires services through the SDK, not through a shared Dart object.
class RemoteDemoService {
  static final RemoteServiceKey<RemoteDemoService> key =
      RemoteServiceKey<RemoteDemoService>(
        serviceId: ServiceId('headunit.demo'),
        create: RemoteDemoService._,
      );

  final RemoteServiceHandle _remote;

  RemoteDemoService._(this._remote);

  Future<String> getStatus() async {
    final Object? response = await _remote.invoke('getStatus');
    if (response is! Map || response['status'] is! String) {
      throw const FormatException('Invalid response from headunit.demo.');
    }
    return response['status'] as String;
  }
}
