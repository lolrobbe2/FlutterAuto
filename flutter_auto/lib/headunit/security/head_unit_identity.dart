import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class HeadUnitIdentity {
  HeadUnitIdentity({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _certificateKey = 'head_unit_certificate_pem';
  static const String _privateKeyKey = 'head_unit_private_key_pem';

  final FlutterSecureStorage _storage;

  Future<String?> readCertificate() {
    return _storage.read(key: _certificateKey);
  }

  Future<String?> readPrivateKey() {
    return _storage.read(key: _privateKeyKey);
  }

  Future<void> saveIdentity({
    required String certificatePem,
    required String privateKeyPem,
  }) async {
    if (certificatePem.trim().isEmpty || privateKeyPem.trim().isEmpty) {
      throw ArgumentError('Certificate and private key must not be empty.');
    }

    // Save the private key first. If either operation fails, surface the
    // error rather than silently starting with an incomplete identity.
    await _storage.write(key: _privateKeyKey, value: privateKeyPem);
    await _storage.write(key: _certificateKey, value: certificatePem);
  }

  Future<bool> hasIdentity() async {
    final String? certificate = await readCertificate();
    final String? privateKey = await readPrivateKey();

    return certificate != null &&
        certificate.isNotEmpty &&
        privateKey != null &&
        privateKey.isNotEmpty;
  }
}
