import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_auto_shared_platform_interface.dart';

/// An implementation of [FlutterAutoSharedPlatform] that uses method channels.
class MethodChannelFlutterAutoShared extends FlutterAutoSharedPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_auto_shared');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
