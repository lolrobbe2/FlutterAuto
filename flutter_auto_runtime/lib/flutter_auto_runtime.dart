// You have generated a new plugin project without specifying the `--platforms`
// flag. A plugin project with no platform support was generated. To add a
// platform, run `flutter create -t plugin --platforms <platforms> .` under the
// same directory. You can also find a detailed instruction on how to add
// platforms in the `pubspec.yaml` at
// https://flutter.dev/to/pubspec-plugin-platforms.


import 'package:flutter/widgets.dart';
import 'package:flutter_auto_runtime/navigation/heaunit_router.dart';

class FlutterAutoRuntime {
  late final HeaunitRouter router;
  FlutterAutoRuntime() {
    router = HeaunitRouter();
  }

  Widget get navigator => Router<void>(routerDelegate: router);

  void dispose() {
    router.dispose();
  }
}

class FlutterAutoApp extends StatelessWidget {
  const FlutterAutoApp({
    super.key,
    required this.runtime,
  });

  final FlutterAutoRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: const Color(0xFFFFFFFF),
      home: runtime.navigator,
    );
  }
}