import 'package:flutter/foundation.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

import 'application_process_launcher.dart';
import 'external_flutter_application_instance.dart';
import 'flutter_application_instance.dart';
import 'flutter_application_package_installer.dart';

/// Runs registered Dart factories in-process and installed Windows HAPP
/// packages in a separate process.
///
/// Keeping both modes behind the existing Flutter runtime kind means the
/// application manager and shell don't need a second runtime registration or
/// a different lifecycle contract.
class FlutterApplicationRuntime implements ApplicationRuntime {
  static const Set<TargetPlatform> _supportedPlatforms = {
    TargetPlatform.android,
    TargetPlatform.windows,
  };

  final Map<ApplicationId, HeadunitApplicationFactory> _factories = {};
  final Map<ApplicationId, InstalledFlutterApplication> _installedApplications =
      {};
  final ApplicationProcessLauncher _processLauncher;

  /// The host selects the media format. The child must send access units that
  /// match this configuration.
  final VideoStreamConfiguration mediaConfiguration;

  bool _disposed = false;

  FlutterApplicationRuntime({
    ApplicationProcessLauncher? processLauncher,
    this.mediaConfiguration = VideoStreamConfiguration.defaultConfiguration,
  }) : _processLauncher =
           processLauncher ?? WindowsApplicationProcessLauncher();

  @override
  ApplicationRuntimeKind get kind => ApplicationRuntimeKind.flutter;

  /// Registers an in-process Dart factory (the existing SDK behavior).
  void registerApplication({
    required ApplicationId id,
    required HeadunitApplicationFactory factory,
  }) {
    _ensureActive();

    if (_factories.containsKey(id) || _installedApplications.containsKey(id)) {
      throw StateError('Flutter application $id is already registered.');
    }

    _factories[id] = factory;
  }

  /// Registers an already extracted .happ package for external execution.
  ///
  /// The first external process launcher supports Windows .exe targets. Other
  /// platforms can be added behind [ApplicationProcessLauncher] later.
  void registerInstalledApplication(InstalledFlutterApplication application) {
    _ensureActive();

    final ApplicationId id = application.application.id;
    if (_factories.containsKey(id) || _installedApplications.containsKey(id)) {
      throw StateError('Flutter application $id is already registered.');
    }
    if (application.application.runtime != kind) {
      throw ArgumentError('Installed application $id is not a Flutter app.');
    }

    _installedApplications[id] = application;
  }

  void unregisterApplication(ApplicationId id) {
    _ensureActive();
    _factories.remove(id);
    _installedApplications.remove(id);
  }

  bool isRegistered(ApplicationId id) {
    return _factories.containsKey(id) || _installedApplications.containsKey(id);
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
        'Application identity mismatch when creating ${manifest.id}.',
      );
    }

    final InstalledFlutterApplication? installed =
        _installedApplications[manifest.id];
    if (installed != null) {
      if (defaultTargetPlatform != TargetPlatform.windows ||
          installed.target.platform != FlutterApplicationPlatform.windows) {
        throw UnsupportedError(
          'External Flutter applications currently support Windows targets.',
        );
      }
      if (serviceBroker is! RemoteServiceBroker) {
        throw StateError(
          'External Flutter applications require a RemoteServiceBroker.',
        );
      }

      return ExternalFlutterApplicationInstance(
        id: manifest.id,
        context: context,
        serviceBroker: serviceBroker,
        installedApplication: installed,
        processLauncher: _processLauncher,
        mediaConfiguration: mediaConfiguration,
      );
    }

    final HeadunitApplicationFactory? factory = _factories[manifest.id];
    if (factory == null) {
      throw StateError(
        'No Flutter application factory or installed package registered '
        'for ${manifest.id}.',
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
    _installedApplications.clear();
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
