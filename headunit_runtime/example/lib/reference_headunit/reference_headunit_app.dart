import 'package:material_ui/material_ui.dart';
import 'package:headunit_runtime/headunit_runtime.dart';

/// A compact host-side reference implementation for a FlutterAuto headunit.
///
/// Applications publish semantic [HeadunitUiPage] descriptions; this widget
/// owns the layout, navigation affordance, and theme used by the standard
/// component renderer. Applications never choose their own shell styling.
class ReferenceHeadunitApp extends StatelessWidget {
  final ApplicationManager applicationManager;

  const ReferenceHeadunitApp({super.key, required this.applicationManager});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF35B8A6),
        brightness: Brightness.dark,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        HeadunitUiTheme(
          pagePadding: 28,
          sectionSpacing: 20,
          cardRadius: 22,
          carouselItemWidth: 248,
          carouselHeight: 236,
          buttonHeight: 56,
        ),
      ],
    );

    return MaterialApp(
      title: 'FlutterAuto Reference Headunit',
      theme: theme,
      home: Builder(
        builder: (BuildContext context) {
          return Scaffold(
            body: SafeArea(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.directions_car_filled_outlined),
                        const SizedBox(width: 12),
                        Text(
                          'FLUTTERAUTO',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        const Icon(Icons.wifi),
                        const SizedBox(width: 8),
                        const Text('Ready'),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: HeadunitShell(
                      applicationManager: applicationManager,
                      homeBuilder: (BuildContext context) {
                        return _ReferenceHeadunitHome(
                          applicationManager: applicationManager,
                        );
                      },
                      layoutBuilder: (BuildContext context, Widget surface) {
                        final ApplicationId? foregroundId =
                            applicationManager.foregroundApplicationId;
                        final String? foregroundName = foregroundId == null
                            ? null
                            : applicationManager
                                  .registrations[foregroundId]
                                  ?.manifest
                                  .name;

                        return Column(
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: Row(
                                children: <Widget>[
                                  IconButton(
                                    tooltip: 'Home',
                                    onPressed: foregroundId == null
                                        ? null
                                        : () {
                                            applicationManager.setBackground(
                                              foregroundId,
                                            );
                                          },
                                    icon: const Icon(Icons.home_outlined),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      foregroundName ?? 'Home',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: surface,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReferenceHeadunitHome extends StatefulWidget {
  final ApplicationManager applicationManager;

  const _ReferenceHeadunitHome({required this.applicationManager});

  @override
  State<_ReferenceHeadunitHome> createState() => _ReferenceHeadunitHomeState();
}

class _ReferenceHeadunitHomeState extends State<_ReferenceHeadunitHome> {
  ApplicationId? _launching;
  String? _error;

  Future<void> _launch(ApplicationId id) async {
    if (_launching != null) return;

    setState(() {
      _launching = id;
      _error = null;
    });

    try {
      await widget.applicationManager.launch(id);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _launching = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<ApplicationRegistration> registrations =
        widget.applicationManager.registrations.values.toList()..sort(
          (ApplicationRegistration left, ApplicationRegistration right) =>
              left.manifest.name.compareTo(right.manifest.name),
        );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Applications',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose an installed application. Its standard UI is rendered here '
            'by the headunit theme.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Expanded(
            child: registrations.isEmpty
                ? const Center(child: Text('No applications are registered.'))
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 360,
                          mainAxisExtent: 132,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    itemCount: registrations.length,
                    itemBuilder: (BuildContext context, int index) {
                      final ApplicationRegistration registration =
                          registrations[index];
                      final ApplicationManifest manifest =
                          registration.manifest;
                      final bool isLaunching = _launching == manifest.id;

                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _launching == null
                              ? () => _launch(manifest.id)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  Icons.apps,
                                  size: 34,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        manifest.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        manifest.id.value,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (isLaunching)
                                  const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
