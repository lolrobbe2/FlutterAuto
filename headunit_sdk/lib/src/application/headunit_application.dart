import 'package:flutter/widgets.dart';

import 'headunit_application_context.dart';

abstract class HeadunitApplication {
  const HeadunitApplication();

  Widget build(HeadunitApplicationContext context);

  Future<void> onStart(HeadunitApplicationContext context) async {}

  Future<void> onForeground(HeadunitApplicationContext context) async {}

  Future<void> onBackground(HeadunitApplicationContext context) async {}

  Future<void> onStop(HeadunitApplicationContext context) async {}

  Future<void> onSuspend(HeadunitApplicationContext context) async {}

  Future<void> onResume(HeadunitApplicationContext context) async {}
}

typedef HeadunitApplicationFactory = HeadunitApplication Function();
