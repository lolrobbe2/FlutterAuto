import 'package:flutter/widgets.dart';
import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:headunit_sdk/headunit_sdk.dart';
import 'package:headunit_runtime/headunit_runtime.dart';

class RuntimeExampleApplication extends HeadunitApplication {
  @override
  Widget build(HeadunitApplicationContext context) {
    return Center(
      child: Text(
        'Hello from ${context.applicationId}!',
      ),
    );
  }

  @override
  Future<void> onStart(
    HeadunitApplicationContext context,
  ) async {
    final AudioService audioService =
        context.getService(AudioService.serviceKey);

    print(
      'Application started. Audio initialized: '
      '${audioService.isInitialized}',
    );
  }

  @override
  Future<void> onForeground(
    HeadunitApplicationContext context,
  ) async {
    print('Example application foregrounded.');
  }

  @override
  Future<void> onBackground(
    HeadunitApplicationContext context,
  ) async {
    print('Example application backgrounded.');
  }

  @override
  Future<void> onStop(
    HeadunitApplicationContext context,
  ) async {
    print('Example application stopped.');
  }
}