import 'package:flutter/widgets.dart';
import 'package:headunit_contracts/headunit_contracts.dart';

import '../application/application_manager.dart';
import '../application/application_manager_event.dart';
import '../application/flutter_application_instance.dart';

typedef HeadunitShellLayoutBuilder = Widget Function(
  BuildContext context,
  Widget applicationSurface,
);

typedef HeadunitApplicationSurfaceBuilder = Widget Function(
  BuildContext context,
  ApplicationInstance instance,
);

class HeadunitShell extends StatelessWidget {
  final ApplicationManager applicationManager;

  /// Displayed when no application is in the foreground.
  final WidgetBuilder homeBuilder;

  /// Allows the product integrator to define the shell layout.
  final HeadunitShellLayoutBuilder? layoutBuilder;

  /// Optional renderer for application types other than Flutter.
  final HeadunitApplicationSurfaceBuilder? applicationBuilder;

  const HeadunitShell({
    super.key,
    required this.applicationManager,
    required this.homeBuilder,
    this.layoutBuilder,
    this.applicationBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ApplicationManagerEvent>(
      stream: applicationManager.events,
      builder: (
        BuildContext context,
        AsyncSnapshot<ApplicationManagerEvent> snapshot,
      ) {
        final ApplicationId? foregroundId =
            applicationManager.foregroundApplicationId;

        final Map<ApplicationId, ApplicationInstance> instances =
            applicationManager.runningApplications;

        final List<Widget> applicationSurfaces = [];

        for (final MapEntry<ApplicationId, ApplicationInstance> entry
            in instances.entries) {
          final ApplicationInstance instance = entry.value;

          final bool isForeground = entry.key == foregroundId;

          applicationSurfaces.add(
            Positioned.fill(
              child: Offstage(
                offstage: !isForeground,
                child: TickerMode(
                  enabled: isForeground,
                  child: KeyedSubtree(
                    key: ObjectKey(instance),
                    child: _buildApplicationSurface(
                      context,
                      instance,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final bool foregroundExists =
            foregroundId != null &&
            instances.containsKey(foregroundId);

        if (!foregroundExists) {
          applicationSurfaces.add(
            Positioned.fill(
              child: homeBuilder(context),
            ),
          );
        }

        final Widget applicationSurface = Stack(
          fit: StackFit.expand,
          children: applicationSurfaces,
        );

        return layoutBuilder?.call(
              context,
              applicationSurface,
            ) ??
            applicationSurface;
      },
    );
  }

  Widget _buildApplicationSurface(
    BuildContext context,
    ApplicationInstance instance,
  ) {
    if (applicationBuilder != null) {
      return applicationBuilder!(context, instance);
    }

    if (instance is FlutterApplicationInstance) {
      return instance.widget;
    }

    throw UnsupportedError(
      'No application surface renderer registered for '
      '${instance.runtimeType}.',
    );
  }
}