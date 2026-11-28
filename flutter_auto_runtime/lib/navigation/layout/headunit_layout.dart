import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
abstract interface class HeadunitLayout implements Widget {
  ValueListenable<Widget> get center;
  void setCenter(Widget value);
}