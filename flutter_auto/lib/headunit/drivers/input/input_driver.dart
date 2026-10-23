import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_auto/headunit/input/touch_input.dart';

/// Base widget for input drivers.
///
/// Different drivers can wrap the same display widget and provide
/// different interaction models.
abstract class InputDriver extends StatefulWidget {
  const InputDriver({
    super.key,
    required this.child,
  });

  final Widget child;
}
