import 'package:flutter/widgets.dart';

abstract class StatusIcon extends StatelessWidget {
  const StatusIcon({
    super.key,
    this.visible = true,
  });

  final bool visible;

  // Click interactions
  void onClicked() {}
  void onDoubleClicked() {}
  void onLongPressed() {}
  void onSecondaryClicked() {}

  // Press interactions
  void onTapDown(TapDownDetails details) {}
  void onTapUp(TapUpDetails details) {}
  void onTapCancel() {}

  // Mouse / pointer interactions
  void onHoverChanged(bool hovered) {}
}