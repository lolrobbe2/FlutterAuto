import 'package:flutter/widgets.dart';

class HeaunitRouter extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }

  @override
  Future<void> setNewRoutePath(Object configuration) async {}

  @override
  Future<void> setInitialRoutePath(Object configuration) async {}

  @override
  Future<void> setRestoredRoutePath(Object configuration) async {}
}
