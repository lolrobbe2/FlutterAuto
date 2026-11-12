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

  final WidgetBuilder homeBuilder;

  final HeadunitShellLayoutBuilder? layoutBuilder;

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
      builder:
          (
            BuildContext context,
            AsyncSnapshot<ApplicationManagerEvent> snapshot,
          ) {
            final ApplicationId? foregroundId =
                applicationManager.foregroundApplicationId;

            final List<MapEntry<ApplicationId, ApplicationInstance>>
            instances = applicationManager.runningApplications.entries
                .where((MapEntry<ApplicationId, ApplicationInstance> entry) {
                  return entry.value.state ==
                          ApplicationLifecycleState.foreground ||
                      entry.value.state == ApplicationLifecycleState.background;
                })
                .toList(growable: false);
            // Index zero is always the home screen.
            int activeIndex = 0;

            final List<Widget> children = [
              KeyedSubtree(
                key: const ValueKey<String>('headunit-home'),
                child: homeBuilder(context),
              ),
            ];

            for (int index = 0; index < instances.length; index++) {
              final MapEntry<ApplicationId, ApplicationInstance> entry =
                  instances[index];

              if (entry.key == foregroundId) {
                activeIndex = index + 1;
              }

              children.add(
                KeyedSubtree(
                  key: ValueKey<ApplicationId>(entry.key),
                  child: TickerMode(
                    enabled: entry.key == foregroundId,
                    child: _buildApplicationSurface(context, entry.value),
                  ),
                ),
              );
            }

            final Widget applicationSurface = IndexedStack(
              index: activeIndex,
              sizing: StackFit.expand,
              children: children,
            );

            return layoutBuilder?.call(context, applicationSurface) ??
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
