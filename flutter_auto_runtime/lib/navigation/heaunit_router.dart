import 'package:flutter/widgets.dart';

class HeaunitRouter extends RouterDelegate<void>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<void> {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }

  @override
  Future<void> setNewRoutePath(void configuration) async {
    
  }

  @override
  Future<void> setInitialRoutePath(void configuration) async {

  }

  @override
  Future<void> setRestoredRoutePath(void configuration) async {

  }

  @override
  void dispose() {
    super.dispose();
  }
}
