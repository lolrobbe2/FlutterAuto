import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_auto_runtime/flutter_auto_runtime.dart';

void main() {
  final FlutterAutoRuntime runtime = FlutterAutoRuntime();

  runApp(
    HeadunitApp(runtime: runtime),
  );
}
