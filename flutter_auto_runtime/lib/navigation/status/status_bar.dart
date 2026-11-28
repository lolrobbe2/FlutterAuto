import 'package:flutter/widgets.dart';
import 'package:flutter_auto_runtime/navigation/status/status_icon.dart';

class HeadunitStatusBar extends StatelessWidget {
  const HeadunitStatusBar({super.key, required this.statusIcons});

  final List<StatusIcon> statusIcons;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: statusIcons
          .where((StatusIcon icon) => icon.visible)
          .map(
            (StatusIcon icon) => MouseRegion(
              onEnter: (_) => icon.onHoverChanged(true),
              onExit: (_) => icon.onHoverChanged(false),
              child: GestureDetector(
                onTap: icon.onClicked,
                onDoubleTap: icon.onDoubleClicked,
                onLongPress: icon.onLongPressed,
                onSecondaryTap: icon.onSecondaryClicked,
                onTapDown: icon.onTapDown,
                onTapUp: icon.onTapUp,
                onTapCancel: icon.onTapCancel,
                child: icon,
              ),
            ),
          )
          .toList(),
    );
  }
}
