import 'package:flutter/widgets.dart';
import 'package:flutter_auto_headunit/home_page.dart';
import 'package:flutter_auto_headunit/status_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_auto_runtime/flutter_auto_runtime.dart';



void main() {
  final ColumnLayout layout = ColumnLayout(
    statusBar: const HeadunitStatusBar(
      statusIcons: [
        WifiStatusIcon(),
        BluetoothStatusIcon(),
        GpsStatusIcon(),
        BatteryStatusIcon(),
      ],
    ),
  );

  layout.setCenter(const HomePage());

  final FlutterAutoRuntime runtime = FlutterAutoRuntime(
    layout: layout,
  );

  runApp(HeadunitApp(runtime: runtime));
}