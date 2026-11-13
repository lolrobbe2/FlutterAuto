import 'dart:async';

import 'package:headunit_shared/headunit_shared_io.dart';

typedef RemoteServiceMethodHandler = FutureOr<Object?> Function(
  Map<String, Object?> arguments,
);

/// Exposes a small, explicitly allow-listed RPC surface for an existing
/// headunit service.
///
/// Parameters and return values must be JSON-compatible. Bulk binary data
/// (audio samples, video packets, images) belongs on a dedicated media channel.
class RemoteServiceAdapter {
  final ServiceId serviceId;
  final Set<CapabilityId> requiredCapabilities;
  final Map<String, RemoteServiceMethodHandler> _handlers;

  RemoteServiceAdapter({
    required this.serviceId,
    required Map<String, RemoteServiceMethodHandler> methods,
    Iterable<CapabilityId> requiredCapabilities = const <CapabilityId>[],
  }) : requiredCapabilities = Set<CapabilityId>.unmodifiable(
         requiredCapabilities,
       ),
       _handlers = Map<String, RemoteServiceMethodHandler>.unmodifiable(methods) {
    if (_handlers.isEmpty) {
      throw ArgumentError('A remote service must expose at least one method.');
    }
    for (final String method in _handlers.keys) {
      if (method.trim().isEmpty || method.length > 128) {
        throw ArgumentError.value(method, 'methods', 'Invalid RPC method name.');
      }
    }
  }

  List<String> get methods {
    final List<String> result = _handlers.keys.toList(growable: false)..sort();
    return List<String>.unmodifiable(result);
  }

  Future<Object?> invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final RemoteServiceMethodHandler? handler = _handlers[method];
    if (handler == null) {
      throw RemoteServiceMethodNotFoundException(serviceId, method);
    }
    return await handler(arguments);
  }
}

class RemoteServiceMethodNotFoundException implements Exception {
  final ServiceId serviceId;
  final String method;

  const RemoteServiceMethodNotFoundException(this.serviceId, this.method);

  @override
  String toString() => 'Remote method "$method" is not exposed by $serviceId.';
}
