import 'package:flutter/services.dart';

class AssetIdentityLoader {
  static const String _certificatePath = 'assets/security/headunit-cert.pem';

  static const String _privateKeyPath = 'assets/security/headunit-key.pem';

  Future<String> loadCertificatePem() {
    return rootBundle.loadString(_certificatePath);
  }

  Future<String> loadPrivateKeyPem() {
    return rootBundle.loadString(_privateKeyPath);
  }
}
