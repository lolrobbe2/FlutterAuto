// You have generated a new plugin project without specifying the `--platforms`
// flag. A plugin project with no platform support was generated. To add a
// platform, run `flutter create -t plugin --platforms <platforms> .` under the
// same directory. You can also find a detailed instruction on how to add
// platforms in the `pubspec.yaml` at
// https://flutter.dev/to/pubspec-plugin-platforms.

import 'package:flutter/widgets.dart';

import 'package:flutter_auto_runtime/navigation/navigation.dart';

export 'package:flutter_auto_runtime/navigation/navigation.dart';
export 'package:flutter_auto_runtime/widgets/headunit_app.dart';
export 'package:flutter_auto_runtime/runtime/windows.dart';
class FlutterAutoRuntime {
  late final HeadunitRouter _router;
  final HeadunitLayout layout;
  FlutterAutoRuntime({required this.layout}) {
    _router = HeadunitRouter(layout: layout);
  }

  Widget get navigator => Router<void>(routerDelegate: _router);
  RouterDelegate<Object>? get router => _router;
  void dispose() {
    _router.dispose();
  }

}

class FlutterAutoApp extends StatelessWidget {
  const FlutterAutoApp({super.key, required this.runtime});

  final FlutterAutoRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(color: const Color(0xFFFFFFFF), home: runtime.navigator);
  }
}
