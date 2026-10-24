typedef PemProvider = Future<String> Function();

/// Loads the TLS certificate and private key from an application-provided
/// source, without requiring either credential to be bundled as an asset.
class AssetIdentityLoader {
  const AssetIdentityLoader({
    required this._certificateProvider,
    required PemProvider privateKeyProvider,
  })  : _privateKeyProvider = privateKeyProvider;

  final PemProvider _certificateProvider;
  final PemProvider _privateKeyProvider;

  Future<String> loadCertificatePem() => _certificateProvider();

  Future<String> loadPrivateKeyPem() => _privateKeyProvider();
}