import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_auto_runtime/flutter_auto_runtime.dart';
import 'package:flutter_auto_runtime/flutter_auto_runtime_platform_interface.dart';
import 'package:flutter_auto_runtime/flutter_auto_runtime_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterAutoRuntimePlatform
    with MockPlatformInterfaceMixin
    implements FlutterAutoRuntimePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterAutoRuntimePlatform initialPlatform = FlutterAutoRuntimePlatform.instance;

  test('$MethodChannelFlutterAutoRuntime is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterAutoRuntime>());
  });

  test('getPlatformVersion', () async {
    FlutterAutoRuntime flutterAutoRuntimePlugin = FlutterAutoRuntime();
    MockFlutterAutoRuntimePlatform fakePlatform = MockFlutterAutoRuntimePlatform();
    FlutterAutoRuntimePlatform.instance = fakePlatform;

    expect(await flutterAutoRuntimePlugin.getPlatformVersion(), '42');
  });
}
