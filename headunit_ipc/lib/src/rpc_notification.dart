class RpcNotification {
  final String method;
  final Map<String, Object?> parameters;

  const RpcNotification({
    required this.method,
    required this.parameters,
  });
}
