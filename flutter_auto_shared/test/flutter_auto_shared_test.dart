import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_auto_shared/flutter_auto_shared.dart';
import 'package:flutter_auto_shared/flutter_auto_shared_platform_interface.dart';
import 'package:flutter_auto_shared/flutter_auto_shared_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterAutoSharedPlatform
    with MockPlatformInterfaceMixin
    implements FlutterAutoSharedPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterAutoSharedPlatform initialPlatform = FlutterAutoSharedPlatform.instance;

  test('$MethodChannelFlutterAutoShared is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterAutoShared>());
  });

  test('getPlatformVersion', () async {
    FlutterAutoShared flutterAutoSharedPlugin = FlutterAutoShared();
    MockFlutterAutoSharedPlatform fakePlatform = MockFlutterAutoSharedPlatform();
    FlutterAutoSharedPlatform.instance = fakePlatform;

    expect(await flutterAutoSharedPlugin.getPlatformVersion(), '42');
  });
}
