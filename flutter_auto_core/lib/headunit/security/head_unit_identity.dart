import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

class HeadUnitIdentity {
  static final Logger _log = Logger('HeadUnitIdentity');

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
      final String certificate = await readCertificate();
      final String privateKey = await readPrivateKey();

      return certificate.trim().isNotEmpty && privateKey.trim().isNotEmpty;
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to load the bundled head unit identity.',
        error,
        stackTrace,
      );
      return false;
    }
  }

  /// Loads the certificate and private key from bundled Flutter assets.
  ///
  /// Call this before initializing the TLS client.
  Future<void> ensureIdentity() async {
    final String certificate = await readCertificate();
    final String privateKey = await readPrivateKey();

    if (certificate.trim().isEmpty || privateKey.trim().isEmpty) {
      throw StateError('The certificate or private key asset is empty.');
    }

    _log.fine('Bundled head unit identity loaded successfully.');
  }

  /// Logs the certificate PEM for debugging.
  ///
  /// Avoid logging private key material.
  Future<String?> debugCertificatePem() async {
    try {
      final String certificate = await readCertificate();
      _log.fine('Loaded head unit certificate PEM:\n$certificate');
      return certificate;
    } catch (error, stackTrace) {
      _log.warning('Failed to load certificate asset.', error, stackTrace);
      return null;
    }
  }
}
