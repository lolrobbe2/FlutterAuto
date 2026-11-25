import 'package:flutter/widgets.dart';

class HeaunitPage<T> extends Page<T> {
  const HeaunitPage({
    required this.child,
    required this.icon,
    super.key,
    super.name,
    super.arguments,
  });

  final Widget child;
  final IconData icon;

  @override
  Route<T> createRoute(BuildContext context) {
    return PageRouteBuilder<T>( 
      settings: this,
      pageBuilder: (context, animation, secondaryAnimation) => child,
    );
  }
}
