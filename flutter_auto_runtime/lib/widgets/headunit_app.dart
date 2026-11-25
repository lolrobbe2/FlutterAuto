import 'package:flutter/widgets.dart';
import 'package:flutter_auto_runtime/flutter_auto_runtime.dart';

class HeadunitApp extends StatelessWidget {
  const HeadunitApp({super.key, required this.runtime});

  final FlutterAutoRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp.router(
      color: const Color(0xFFFFFFFF),
      routerDelegate: runtime.router,
    );
  }
}
