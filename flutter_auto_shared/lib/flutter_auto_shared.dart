
import 'flutter_auto_shared_platform_interface.dart';

class FlutterAutoShared {
  Future<String?> getPlatformVersion() {
    return FlutterAutoSharedPlatform.instance.getPlatformVersion();
  }
}
