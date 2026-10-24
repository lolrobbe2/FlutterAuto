import 'dart:typed_data';

abstract interface class ProtocolTransport {
  Stream<List<int>> get input;

  Future<void> write(Uint8List bytes);

  Future<void> close();

  /// Immediately aborts the transport after a protocol failure.
  Future<void> abort();
}