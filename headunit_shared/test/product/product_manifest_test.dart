import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:test/test.dart';

void main() {
  group('ProductManifest', () {
    final ApplicationId radioId = ApplicationId('com.vendor.radio');

    final ApplicationId navigationId = ApplicationId('com.vendor.navigation');

    final CapabilityId audioPlayback = CapabilityId('audio.playback');

    final ProductManifest product = ProductManifest(
      id: ProductId('com.vendor.premium_headunit'),
      name: 'Premium Head Unit',
      version: '1.0.0',
      minimumFrameworkVersion: '1.0.0',
      applications: [
        ProductApplication(
          id: radioId,
          packagePath: 'applications/radio.happ',
          backgroundPolicy: ApplicationBackgroundPolicy.keepMounted,
          grantedCapabilities: [audioPlayback],
        ),
        ProductApplication(
          id: navigationId,
          packagePath: 'applications/navigation.happ',
          backgroundPolicy: ApplicationBackgroundPolicy.suspend,
        ),
      ],
      modules: [
        ProductModule(
          id: ModuleId('com.vendor.audio'),
          packagePath: 'modules/audio',
        ),
        ProductModule(
          id: ModuleId('com.vendor.gps'),
          packagePath: 'modules/gps',
        ),
      ],
    );

    test('serializes and deserializes the product manifest', () {
      final Map<String, Object?> json = product.toJson();

      final ProductManifest decoded = ProductManifest.fromJson(json);

      expect(decoded.toJson(), equals(json));
      expect(decoded.id, product.id);
      expect(decoded.applications, hasLength(2));
      expect(decoded.modules, hasLength(2));
    });

    test('stores Flutter and web packages using the same package format', () {
      final ProductManifest packageProduct = ProductManifest(
        id: ProductId('com.vendor.test'),
        name: 'Package Test',
        version: '1.0.0',
        minimumFrameworkVersion: '1.0.0',
        applications: [
          ProductApplication(
            id: radioId,
            packagePath: 'applications/radio.happ',
          ),
          ProductApplication(
            id: navigationId,
            packagePath: 'applications/navigation.happ',
          ),
        ],
      );

      expect(
        packageProduct.applications.map(
          (ProductApplication app) => app.packagePath.endsWith('.happ'),
        ),
        everyElement(isTrue),
      );

      // Runtime type is defined by the embedded application manifest,
      // not by the product application entry.
      final ApplicationManifest flutterManifest = ApplicationManifest(
        id: radioId,
        name: 'Radio',
        version: '1.0.0',
        minimumFrameworkVersion: '1.0.0',
        runtime: ApplicationRuntimeKind.flutter,
        requestedCapabilities: [audioPlayback],
      );

      final ApplicationManifest webManifest = ApplicationManifest(
        id: navigationId,
        name: 'Navigation',
        version: '1.0.0',
        minimumFrameworkVersion: '1.0.0',
        runtime: ApplicationRuntimeKind.web,
        entryPoint: 'index.html',
      );

      packageProduct.applications[0].validateAgainstManifest(flutterManifest);

      packageProduct.applications[1].validateAgainstManifest(webManifest);
    });

    test('preserves application background policies', () {
      final ProductManifest decoded = ProductManifest.fromJson(
        product.toJson(),
      );

      expect(
        decoded.applications[0].backgroundPolicy,
        ApplicationBackgroundPolicy.keepMounted,
      );

      expect(
        decoded.applications[1].backgroundPolicy,
        ApplicationBackgroundPolicy.suspend,
      );
    });

    test('rejects duplicate application IDs', () {
      expect(
        () => ProductManifest(
          id: ProductId('com.vendor.test'),
          name: 'Test',
          version: '1.0.0',
          minimumFrameworkVersion: '1.0.0',
          applications: [
            ProductApplication(
              id: radioId,
              packagePath: 'applications/radio.happ',
            ),
            ProductApplication(
              id: radioId,
              packagePath: 'applications/another_radio.happ',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate module IDs', () {
      expect(
        () => ProductManifest(
          id: ProductId('com.vendor.test'),
          name: 'Test',
          version: '1.0.0',
          minimumFrameworkVersion: '1.0.0',
          modules: [
            ProductModule(
              id: ModuleId('com.vendor.audio'),
              packagePath: 'modules/audio',
            ),
            ProductModule(
              id: ModuleId('com.vendor.audio'),
              packagePath: 'modules/audio2',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate application package paths', () {
      expect(
        () => ProductManifest(
          id: ProductId('com.vendor.test'),
          name: 'Test',
          version: '1.0.0',
          minimumFrameworkVersion: '1.0.0',
          applications: [
            ProductApplication(
              id: radioId,
              packagePath: 'applications/radio.happ',
            ),
            ProductApplication(
              id: navigationId,
              packagePath: 'applications/radio.happ',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects unsafe application package paths', () {
      expect(
        () => ProductApplication(id: radioId, packagePath: '../radio.happ'),
        throwsArgumentError,
      );

      expect(
        () =>
            ProductApplication(id: radioId, packagePath: 'C:/apps/radio.happ'),
        throwsArgumentError,
      );

      expect(
        () => ProductApplication(
          id: radioId,
          packagePath: 'applications/radio.zip',
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate granted capabilities', () {
      expect(
        () => ProductApplication(
          id: radioId,
          packagePath: 'applications/radio.happ',
          grantedCapabilities: [audioPlayback, audioPlayback],
        ),
        throwsArgumentError,
      );
    });

    test('rejects grants not requested by the application', () {
      final ApplicationManifest manifest = ApplicationManifest(
        id: radioId,
        name: 'Radio',
        version: '1.0.0',
        minimumFrameworkVersion: '1.0.0',
        runtime: ApplicationRuntimeKind.flutter,
      );

      final ProductApplication application = ProductApplication(
        id: radioId,
        packagePath: 'applications/radio.happ',
        grantedCapabilities: [audioPlayback],
      );

      expect(
        () => application.validateAgainstManifest(manifest),
        throwsFormatException,
      );
    });

    test('rejects mismatched package application IDs', () {
      final ApplicationManifest manifest = ApplicationManifest(
        id: navigationId,
        name: 'Navigation',
        version: '1.0.0',
        minimumFrameworkVersion: '1.0.0',
        runtime: ApplicationRuntimeKind.web,
        entryPoint: 'index.html',
      );

      expect(
        () => product.applications[0].validateAgainstManifest(manifest),
        throwsFormatException,
      );
    });

    test('rejects unsupported product manifest schema versions', () {
      final Map<String, Object?> json = product.toJson();
      json['schemaVersion'] = 999;

      expect(() => ProductManifest.fromJson(json), throwsFormatException);
    });

    test('exposes immutable application and module collections', () {
      expect(() => product.applications.clear(), throwsUnsupportedError);

      expect(() => product.modules.clear(), throwsUnsupportedError);

      expect(
        () => product.applications.first.grantedCapabilities.clear(),
        throwsUnsupportedError,
      );
    });
  });
}
