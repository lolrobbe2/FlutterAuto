import 'package:flutter/services.dart';

class HeadUnitIdentity {
  static const String _certificatePath = 'assets/security/headunit-cert.pem';
  static const String _privateKeyPath = 'assets/security/headunit-key.pem';

  Future<String> readCertificate() {
    return rootBundle.loadString(_certificatePath);
  }

  Future<String> readPrivateKey() {
    return rootBundle.loadString(_privateKeyPath);
  }

  Future<bool> hasIdentity() async {
    try {
      final certificate = await readCertificate();
      final privateKey = await readPrivateKey();

      return certificate.trim().isNotEmpty && privateKey.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Loads the certificate and private key from bundled Flutter assets.
  ///
  /// Call this before initializing the TLS client.
  Future<void> ensureIdentity() async {
    final certificate = await readCertificate();
    final privateKey = await readPrivateKey();

    if (certificate.trim().isEmpty || privateKey.trim().isEmpty) {
      throw StateError('The certificate or private key asset is empty.');
    }
  }

  Future<String?> debugCertificatePem() async {
    try {
      final certificate = await readCertificate();
      print(certificate);
      return certificate;
    } catch (error) {
      print('Failed to load certificate asset: $error');
      return null;
    }
  }
}
