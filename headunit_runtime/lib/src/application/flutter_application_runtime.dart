import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

import 'flutter_application_instance.dart';

import 'package:flutter/foundation.dart';

class FlutterApplicationRuntime implements ApplicationRuntime {
  static const Set<TargetPlatform> _supportedPlatforms = {
    TargetPlatform.android,
    TargetPlatform.windows,
  };
  final Map<ApplicationId, HeadunitApplicationFactory> _factories = {};

  bool _disposed = false;

  @override
  ApplicationRuntimeKind get kind => ApplicationRuntimeKind.flutter;

  void registerApplication({
    required ApplicationId id,
    required HeadunitApplicationFactory factory,
  }) {
    _ensureActive();

    if (_factories.containsKey(id)) {
      throw StateError('Flutter application $id is already registered.');
    }

    _factories[id] = factory;
  }

  void unregisterApplication(ApplicationId id) {
    _ensureActive();

    _factories.remove(id);
  }

  bool isRegistered(ApplicationId id) {
    return _factories.containsKey(id);
  }

  @override
  Future<ApplicationInstance> createInstance({
    required ApplicationManifest manifest,
    required ApplicationLaunchContext context,
    required ServiceBroker serviceBroker,
  }) async {
    _ensureActive();

    _ensureSupportedPlatform();

    if (manifest.runtime != kind) {
      throw ArgumentError(
        'FlutterApplicationRuntime cannot execute '
        '${manifest.runtime.name} applications.',
      );
    }

    if (context.applicationId != manifest.id ||
        serviceBroker.applicationId != manifest.id) {
      throw ArgumentError(
        'Application identity mismatch when creating $manifest.id.',
      );
    }

    final HeadunitApplicationFactory? factory = _factories[manifest.id];

    if (factory == null) {
      throw StateError(
        'No Flutter application factory registered for ${manifest.id}.',
      );
    }

    final HeadunitApplication application = factory();

    final HeadunitApplicationContext applicationContext =
        HeadunitApplicationContext(
          applicationId: manifest.id,
          services: serviceBroker,
          locale: context.locale,
          productId: context.productId,
        );

    return FlutterApplicationInstance(
      id: manifest.id,
      application: application,
      context: applicationContext,
    );
  }

  void dispose() {
    _factories.clear();
    _disposed = true;
  }

  void _ensureSupportedPlatform() {
    final TargetPlatform platform = defaultTargetPlatform;

    if (kIsWeb || !_supportedPlatforms.contains(platform)) {
      final String platformName = kIsWeb ? 'web' : platform.name;

      throw UnsupportedError(
        'FlutterApplicationRuntime does not support $platformName. '
        'Supported platforms are native Android and Windows.',
      );
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('FlutterApplicationRuntime has been disposed.');
    }
  }
}
