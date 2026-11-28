import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_auto_runtime/navigation/layout/headunit_layout.dart';
import 'package:flutter_auto_runtime/navigation/status/status_bar.dart';

class ColumnLayout extends StatefulWidget implements HeadunitLayout {
  ColumnLayout({
    super.key,
    required this.statusBar,
  }) : _center = ValueNotifier<Widget>(const SizedBox.shrink());

  final HeadunitStatusBar statusBar;
  final ValueNotifier<Widget> _center;

  @override
  ValueListenable<Widget> get center => _center;

  @override
  void setCenter(Widget value) {
    _center.value = value;
  }

  @override
  State<ColumnLayout> createState() => _ColumnLayoutState();
}

class _ColumnLayoutState extends State<ColumnLayout> {
  @override
  void dispose() {
    widget._center.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        widget.statusBar,
        Expanded(
          child: ValueListenableBuilder<Widget>(
            valueListenable: widget.center,
            builder: (context, currentCenter, child) {
              return Center(child: currentCenter);
            },
          ),
        ),
      ],
    );
  }
}