import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_auto_runtime_platform_interface.dart';

/// An implementation of [FlutterAutoRuntimePlatform] that uses method channels.
class MethodChannelFlutterAutoRuntime extends FlutterAutoRuntimePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_auto_runtime');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
