import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_auto_runtime_method_channel.dart';

abstract class FlutterAutoRuntimePlatform extends PlatformInterface {
  /// Constructs a FlutterAutoRuntimePlatform.
  FlutterAutoRuntimePlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterAutoRuntimePlatform _instance = MethodChannelFlutterAutoRuntime();

  /// The default instance of [FlutterAutoRuntimePlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterAutoRuntime].
  static FlutterAutoRuntimePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterAutoRuntimePlatform] when
  /// they register themselves.
  static set instance(FlutterAutoRuntimePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
