import 'package:flutter_auto_runtime/navigation/layout/headunit_layout.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/widgets.dart';

class HeaunitRouter extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final HeadunitLayout layout;

  new({required this.layout});

  @override
  Widget build(BuildContext context) {
    return layout;
  }

  @override
  Future<void> setNewRoutePath(Object configuration) async {}

  @override
  Future<void> setInitialRoutePath(Object configuration) async {}

  @override
  Future<void> setRestoredRoutePath(Object configuration) async {}
}
