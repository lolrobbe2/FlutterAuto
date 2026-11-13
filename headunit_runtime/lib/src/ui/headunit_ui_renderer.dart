import 'package:material_ui/material_ui.dart';
import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'headunit_ui_theme.dart';

/// Renders the standard declarative headunit components using the host theme.
class HeadunitUiRenderer extends StatelessWidget {
  final HeadunitUiPage page;
  final ValueChanged<String> onAction;

  const HeadunitUiRenderer({
    super.key,
    required this.page,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final HeadunitUiTheme uiTheme =
        theme.extension<HeadunitUiTheme>() ?? const HeadunitUiTheme();
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.all(uiTheme.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(page.title, style: theme.textTheme.headlineMedium),
            if (page.subtitle != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                page.subtitle!,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            SizedBox(height: uiTheme.sectionSpacing),
            Expanded(
              child: SingleChildScrollView(
                child: _buildComponent(context, page.body, uiTheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComponent(
    BuildContext context,
    HeadunitUiComponent component,
    HeadunitUiTheme uiTheme,
  ) {
    final ThemeData theme = Theme.of(context);

    if (component is HeadunitUiColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (
            int index = 0;
            index < component.children.length;
            index++
          ) ...<Widget>[
            if (index > 0) SizedBox(height: uiTheme.sectionSpacing),
            _buildComponent(context, component.children[index], uiTheme),
          ],
        ],
      );
    }

    if (component is HeadunitUiText) {
      final TextStyle? style = switch (component.style) {
        HeadunitUiTextStyle.headline => theme.textTheme.headlineSmall,
        HeadunitUiTextStyle.title => theme.textTheme.titleLarge,
        HeadunitUiTextStyle.body => theme.textTheme.bodyLarge,
        HeadunitUiTextStyle.caption => theme.textTheme.bodySmall,
      };
      return Text(
        component.text,
        style: style,
        maxLines: component.maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    if (component is HeadunitUiImage) {
      return _networkImage(component.url, component.aspectRatio, component.fit);
    }

    if (component is HeadunitUiButton) {
      void callback() => onAction(component.action.id);
      final Widget content = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (component.iconCodePoint != null) ...<Widget>[
            Icon(
              IconData(component.iconCodePoint!, fontFamily: 'MaterialIcons'),
            ),
            const SizedBox(width: 8),
          ],
          Text(component.label),
        ],
      );
      final Widget button = switch (component.variant) {
        HeadunitUiButtonVariant.primary => FilledButton(
          onPressed: callback,
          child: content,
        ),
        HeadunitUiButtonVariant.secondary => OutlinedButton(
          onPressed: callback,
          child: content,
        ),
        HeadunitUiButtonVariant.quiet => TextButton(
          onPressed: callback,
          child: content,
        ),
      };
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: uiTheme.buttonHeight),
        child: button,
      );
    }

    if (component is HeadunitUiCard) {
      final List<Widget> children = <Widget>[
        if (component.imageUrl != null)
          _networkImage(component.imageUrl!, 16 / 9, HeadunitUiImageFit.cover),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(component.title, style: theme.textTheme.titleLarge),
              if (component.subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(component.subtitle!, style: theme.textTheme.bodyMedium),
              ],
              if (component.child != null) ...<Widget>[
                const SizedBox(height: 12),
                _buildComponent(context, component.child!, uiTheme),
              ],
            ],
          ),
        ),
      ];
      final Widget cardChild = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
      return Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(uiTheme.cardRadius),
        ),
        child: component.action == null
            ? cardChild
            : InkWell(
                onTap: () => onAction(component.action!.id),
                child: cardChild,
              ),
      );
    }

    if (component is HeadunitUiCarousel) {
      return SizedBox(
        height: uiTheme.carouselHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: component.items.length,
          separatorBuilder: (BuildContext context, int index) =>
              const SizedBox(width: 12),
          itemBuilder: (BuildContext context, int index) {
            final HeadunitUiCarouselItem item = component.items[index];
            return SizedBox(
              width: uiTheme.carouselItemWidth,
              child: Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(uiTheme.cardRadius),
                ),
                child: InkWell(
                  onTap: () => onAction(item.action.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (item.imageUrl != null)
                        Expanded(
                          child: _networkImage(
                            item.imageUrl!,
                            16 / 9,
                            HeadunitUiImageFit.cover,
                          ),
                        )
                      else
                        Expanded(
                          child: ColoredBox(
                            color: theme.colorScheme.secondaryContainer,
                            child: Icon(
                              Icons.widgets_outlined,
                              size: 48,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.title,
                              style: theme.textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (item.subtitle != null)
                              Text(
                                item.subtitle!,
                                style: theme.textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    if (component is HeadunitUiList) {
      return Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(uiTheme.cardRadius),
        ),
        child: Column(
          children: component.items
              .map((HeadunitUiListItem item) {
                final Widget? leading = item.iconCodePoint == null
                    ? null
                    : Icon(
                        IconData(
                          item.iconCodePoint!,
                          fontFamily: 'MaterialIcons',
                        ),
                      );
                return ListTile(
                  leading: leading,
                  title: Text(item.title),
                  subtitle: item.subtitle == null ? null : Text(item.subtitle!),
                  trailing: item.trailingText == null
                      ? (item.action == null
                            ? null
                            : const Icon(Icons.chevron_right))
                      : Text(item.trailingText!),
                  onTap: item.action == null
                      ? null
                      : () => onAction(item.action!.id),
                );
              })
              .toList(growable: false),
        ),
      );
    }

    if (component is HeadunitUiMediaControls) {
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(uiTheme.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(component.title, style: theme.textTheme.titleLarge),
              if (component.artist != null)
                Text(component.artist!, style: theme.textTheme.bodyMedium),
              if (component.progress != null) ...<Widget>[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: component.progress),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Previous',
                    onPressed: component.previousAction == null
                        ? null
                        : () => onAction(component.previousAction!.id),
                    icon: const Icon(Icons.skip_previous),
                    iconSize: 32,
                  ),
                  IconButton.filled(
                    tooltip: component.isPlaying ? 'Pause' : 'Play',
                    onPressed: component.playPauseAction == null
                        ? null
                        : () => onAction(component.playPauseAction!.id),
                    icon: Icon(
                      component.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    iconSize: 36,
                  ),
                  IconButton(
                    tooltip: 'Next',
                    onPressed: component.nextAction == null
                        ? null
                        : () => onAction(component.nextAction!.id),
                    icon: const Icon(Icons.skip_next),
                    iconSize: 32,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (component is HeadunitUiProgress) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (component.label != null)
            Text(component.label!, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: component.value),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _networkImage(String url, double aspectRatio, HeadunitUiImageFit fit) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Image.network(
        url,
        fit: fit == HeadunitUiImageFit.cover ? BoxFit.cover : BoxFit.contain,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) {
              return ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.broken_image_outlined)),
              );
            },
        loadingBuilder:
            (BuildContext context, Widget child, ImageChunkEvent? progress) {
              if (progress == null) return child;
              return ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: const Center(child: CircularProgressIndicator()),
              );
            },
      ),
    );
  }
}

/// Default surface for an external application using the standard UI protocol.
class HeadunitUiSurface extends StatelessWidget {
  final ValueListenable<HeadunitUiPage?> page;
  final ValueChanged<String> onAction;

  const HeadunitUiSurface({
    super.key,
    required this.page,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HeadunitUiPage?>(
      valueListenable: page,
      builder:
          (BuildContext context, HeadunitUiPage? currentPage, Widget? child) {
            if (currentPage == null) {
              return const Center(
                child: Text(
                  'This application has not published a headunit page yet.',
                ),
              );
            }
            return HeadunitUiRenderer(page: currentPage, onAction: onAction);
          },
    );
  }
}
