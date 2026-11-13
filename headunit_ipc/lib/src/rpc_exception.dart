class RpcException implements Exception {
  final int code;
  final String message;
  final Object? data;

  const RpcException(this.code, this.message, {this.data});

  @override
  String toString() => 'RPC error $code: $message';
}
