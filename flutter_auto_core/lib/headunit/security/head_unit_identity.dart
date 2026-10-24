import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

typedef PemLoader = Future<String> Function();

class HeadUnitIdentity {
  HeadUnitIdentity({
    PemLoader? certificateLoader,
    PemLoader? privateKeyLoader,
    bool? useBundledAssets,
  }) : _certificateLoader = certificateLoader,
       _privateKeyLoader = privateKeyLoader,
       _useBundledAssets = useBundledAssets ?? kDebugMode {
    if ((certificateLoader == null) != (privateKeyLoader == null)) {
      throw ArgumentError(
        'Provide both certificateLoader and privateKeyLoader, or neither.',
      );
    }
  }

  static final Logger _log = Logger('HeadUnitIdentity');

  static const String _certificatePath =
      'packages/flutter_auto_core/assets/security/headunit-cert.pem';

  static const String _privateKeyPath =
      'packages/flutter_auto_core/assets/security/headunit-key.pem';

  final PemLoader? _certificateLoader;
  final PemLoader? _privateKeyLoader;
  final bool _useBundledAssets;

  Future<String> readCertificate() {
    final loader = _certificateLoader;

    if (loader != null) {
      return loader();
    }

    if (_useBundledAssets) {
      return rootBundle.loadString(_certificatePath);
    }

    throw StateError(
      'No head-unit identity provider configured. '
      'Supply certificateLoader and privateKeyLoader for this build.',
    );
  }

  Future<String> readPrivateKey() {
    final loader = _privateKeyLoader;

    if (loader != null) {
      return loader();
    }

    if (_useBundledAssets) {
      return rootBundle.loadString(_privateKeyPath);
    }

    throw StateError(
      'No head-unit identity provider configured. '
      'Supply certificateLoader and privateKeyLoader for this build.',
    );
  }

  Future<bool> hasIdentity() async {
    try {
      final certificate = await readCertificate();
      final privateKey = await readPrivateKey();

      return certificate.trim().isNotEmpty && privateKey.trim().isNotEmpty;
    } catch (error, stackTrace) {
      _log.warning('Failed to load the head-unit identity.', error, stackTrace);
      return false;
    }
  }

  /// Loads and validates that both PEM values are non-empty.
  ///
  /// Call before initializing the TLS client.
  Future<void> ensureIdentity() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

    final identityAssets = manifest
        .listAssets()
        .where((key) => key.contains('headunit-'))
        .toList();

    _log.info('Identity assets in bundle: $identityAssets');
    final certificate = await readCertificate();
    final privateKey = await readPrivateKey();

    if (certificate.trim().isEmpty || privateKey.trim().isEmpty) {
      throw StateError('The certificate or private key is empty.');
    }

    _log.fine(
      'Head-unit identity loaded successfully '
      '(bundled=$_useBundledAssets).',
    );
  }

  /// Returns the public certificate PEM for debugging.
  ///
  /// Never log or expose the private key.
  Future<String?> debugCertificatePem() async {
    try {
      return await readCertificate();
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to load the head-unit certificate.',
        error,
        stackTrace,
      );
      return null;
    }
  }
}
