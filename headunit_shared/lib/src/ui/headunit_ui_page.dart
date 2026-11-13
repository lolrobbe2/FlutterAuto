import 'dart:async';

/// Callback type used by UI actions inside the application process.
typedef HeadunitUiActionCallback = FutureOr<void> Function();

/// A semantic action that the headunit can invoke on behalf of the user.
///
/// [onInvoke] is deliberately local-only. It is never serialized; only [id]
/// crosses the process boundary.
class HeadunitUiAction {
  final String id;
  final HeadunitUiActionCallback? onInvoke;

  HeadunitUiAction({required this.id, this.onInvoke}) {
    _validateIdentifier(id, 'action id');
  }

  Map<String, Object?> toJson() => <String, Object?>{'id': id};

  factory HeadunitUiAction.fromJson(Object? value) {
    final Map<String, Object?> json = _readMap(value, 'action');
    return HeadunitUiAction(id: _readString(json, 'id'));
  }
}

/// A versioned, platform-neutral description of a page rendered by a headunit.
///
/// This is a declarative UI contract, not a serialized Flutter widget tree.
class HeadunitUiPage {
  static const int currentSchemaVersion = 1;

  final String title;
  final String? subtitle;
  final HeadunitUiComponent body;

  HeadunitUiPage({required this.title, this.subtitle, required this.body}) {
    _validateText(title, 'title', maxLength: 160);
    if (subtitle != null) {
      _validateText(subtitle!, 'subtitle', maxLength: 240);
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': currentSchemaVersion,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    'body': body.toJson(),
  };

  factory HeadunitUiPage.fromJson(Object? value) {
    final Map<String, Object?> json = _readMap(value, 'page');
    final Object? rawVersion = json['schemaVersion'];
    if (rawVersion != currentSchemaVersion) {
      throw FormatException(
        'Unsupported headunit UI schema version: $rawVersion.',
      );
    }
    final Object? rawSubtitle = json['subtitle'];
    if (rawSubtitle != null && rawSubtitle is! String) {
      throw const FormatException('Page subtitle must be a string.');
    }
    return HeadunitUiPage(
      title: _readString(json, 'title'),
      subtitle: rawSubtitle as String?,
      body: HeadunitUiComponent.fromJson(json['body']),
    );
  }

  Iterable<HeadunitUiAction> get actions => body.actions;
}

/// Base type for the standard cross-process headunit components.
sealed class HeadunitUiComponent {
  const HeadunitUiComponent();

  Map<String, Object?> toJson();

  Iterable<HeadunitUiAction> get actions;

  static HeadunitUiComponent fromJson(Object? value, {int depth = 0}) {
    if (depth > 8) {
      throw const FormatException('Headunit UI component nesting is too deep.');
    }
    final Map<String, Object?> json = _readMap(value, 'component');
    final String type = _readString(json, 'type');
    switch (type) {
      case 'column':
        return HeadunitUiColumn(
          children: _readComponents(json['children'], depth: depth + 1),
        );
      case 'text':
        return HeadunitUiText(
          text: _readString(json, 'text'),
          style: _readEnum(
            HeadunitUiTextStyle.values,
            json['style'],
            'text style',
            defaultValue: HeadunitUiTextStyle.body,
          ),
          maxLines: _readOptionalInt(json, 'maxLines', min: 1, max: 12),
        );
      case 'image':
        return HeadunitUiImage(
          url: _readString(json, 'url'),
          aspectRatio:
              _readOptionalNumber(json, 'aspectRatio')?.toDouble() ?? 16 / 9,
          fit: _readEnum(
            HeadunitUiImageFit.values,
            json['fit'],
            'image fit',
            defaultValue: HeadunitUiImageFit.cover,
          ),
        );
      case 'button':
        return HeadunitUiButton(
          label: _readString(json, 'label'),
          action: HeadunitUiAction.fromJson(json['action']),
          variant: _readEnum(
            HeadunitUiButtonVariant.values,
            json['variant'],
            'button variant',
            defaultValue: HeadunitUiButtonVariant.primary,
          ),
          iconCodePoint: _readOptionalInt(
            json,
            'iconCodePoint',
            min: 0,
            max: 0x10ffff,
          ),
        );
      case 'card':
        return HeadunitUiCard(
          title: _readString(json, 'title'),
          subtitle: _readOptionalString(json, 'subtitle'),
          imageUrl: _readOptionalImageUrl(json, 'imageUrl'),
          action: json['action'] == null
              ? null
              : HeadunitUiAction.fromJson(json['action']),
          child: json['child'] == null
              ? null
              : HeadunitUiComponent.fromJson(json['child'], depth: depth + 1),
        );
      case 'carousel':
        return HeadunitUiCarousel(items: _readCarouselItems(json['items']));
      case 'list':
        return HeadunitUiList(items: _readListItems(json['items']));
      case 'mediaControls':
        return HeadunitUiMediaControls(
          title: _readString(json, 'title'),
          artist: _readOptionalString(json, 'artist'),
          isPlaying: _readBool(json, 'isPlaying'),
          previousAction: _readOptionalAction(json, 'previousAction'),
          playPauseAction: _readOptionalAction(json, 'playPauseAction'),
          nextAction: _readOptionalAction(json, 'nextAction'),
          progress: _readOptionalNumber(json, 'progress')?.toDouble(),
        );
      case 'progress':
        return HeadunitUiProgress(
          value: _readNumber(json, 'value').toDouble(),
          label: _readOptionalString(json, 'label'),
        );
      default:
        throw FormatException('Unknown headunit UI component type: $type.');
    }
  }
}

class HeadunitUiColumn extends HeadunitUiComponent {
  final List<HeadunitUiComponent> children;

  HeadunitUiColumn({required List<HeadunitUiComponent> children})
    : children = List<HeadunitUiComponent>.unmodifiable(children) {
    if (children.isEmpty || children.length > 32) {
      throw ArgumentError.value(
        children.length,
        'children',
        'Expected 1..32 components.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'column',
    'children': children
        .map((HeadunitUiComponent item) => item.toJson())
        .toList(growable: false),
  };

  @override
  Iterable<HeadunitUiAction> get actions =>
      children.expand((HeadunitUiComponent item) => item.actions);
}

enum HeadunitUiTextStyle { headline, title, body, caption }

class HeadunitUiText extends HeadunitUiComponent {
  final String text;
  final HeadunitUiTextStyle style;
  final int? maxLines;

  HeadunitUiText({
    required this.text,
    this.style = HeadunitUiTextStyle.body,
    this.maxLines,
  }) {
    _validateText(text, 'text', maxLength: 4096);
    if (maxLines != null && (maxLines! < 1 || maxLines! > 12)) {
      throw ArgumentError.value(maxLines, 'maxLines');
    }
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'text',
    'text': text,
    'style': style.name,
    if (maxLines != null) 'maxLines': maxLines,
  };

  @override
  Iterable<HeadunitUiAction> get actions => const <HeadunitUiAction>[];
}

enum HeadunitUiImageFit { cover, contain }

class HeadunitUiImage extends HeadunitUiComponent {
  final String url;
  final double aspectRatio;
  final HeadunitUiImageFit fit;

  HeadunitUiImage({
    required this.url,
    this.aspectRatio = 16 / 9,
    this.fit = HeadunitUiImageFit.cover,
  }) {
    _validateImageUrl(url);
    if (!aspectRatio.isFinite || aspectRatio < 0.25 || aspectRatio > 4) {
      throw ArgumentError.value(aspectRatio, 'aspectRatio');
    }
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'image',
    'url': url,
    'aspectRatio': aspectRatio,
    'fit': fit.name,
  };

  @override
  Iterable<HeadunitUiAction> get actions => const <HeadunitUiAction>[];
}

enum HeadunitUiButtonVariant { primary, secondary, quiet }

class HeadunitUiButton extends HeadunitUiComponent {
  final String label;
  final HeadunitUiAction action;
  final HeadunitUiButtonVariant variant;
  final int? iconCodePoint;

  HeadunitUiButton({
    required this.label,
    required this.action,
    this.variant = HeadunitUiButtonVariant.primary,
    this.iconCodePoint,
  }) {
    _validateText(label, 'label', maxLength: 80);
    if (iconCodePoint != null &&
        (iconCodePoint! < 0 || iconCodePoint! > 0x10ffff)) {
      throw ArgumentError.value(iconCodePoint, 'iconCodePoint');
    }
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'button',
    'label': label,
    'action': action.toJson(),
    'variant': variant.name,
    if (iconCodePoint != null) 'iconCodePoint': iconCodePoint,
  };

  @override
  Iterable<HeadunitUiAction> get actions => <HeadunitUiAction>[action];
}

class HeadunitUiCard extends HeadunitUiComponent {
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final HeadunitUiAction? action;
  final HeadunitUiComponent? child;

  HeadunitUiCard({
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.action,
    this.child,
  }) {
    _validateText(title, 'title', maxLength: 160);
    if (subtitle != null) _validateText(subtitle!, 'subtitle', maxLength: 240);
    if (imageUrl != null) _validateImageUrl(imageUrl!);
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'card',
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (action != null) 'action': action!.toJson(),
    if (child != null) 'child': child!.toJson(),
  };

  @override
  Iterable<HeadunitUiAction> get actions sync* {
    if (action != null) yield action!;
    if (child != null) yield* child!.actions;
  }
}

class HeadunitUiCarouselItem {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final HeadunitUiAction action;

  HeadunitUiCarouselItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    required this.action,
  }) {
    _validateIdentifier(id, 'carousel item id');
    _validateText(title, 'title', maxLength: 160);
    if (subtitle != null) _validateText(subtitle!, 'subtitle', maxLength: 240);
    if (imageUrl != null) _validateImageUrl(imageUrl!);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (imageUrl != null) 'imageUrl': imageUrl,
    'action': action.toJson(),
  };
}

class HeadunitUiCarousel extends HeadunitUiComponent {
  final List<HeadunitUiCarouselItem> items;

  HeadunitUiCarousel({required List<HeadunitUiCarouselItem> items})
    : items = List<HeadunitUiCarouselItem>.unmodifiable(items) {
    if (items.isEmpty || items.length > 24) {
      throw ArgumentError.value(
        items.length,
        'items',
        'Expected 1..24 carousel items.',
      );
    }
    if (items.map((HeadunitUiCarouselItem item) => item.id).toSet().length !=
        items.length) {
      throw ArgumentError.value(
        items,
        'items',
        'Carousel item IDs must be unique.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'carousel',
    'items': items
        .map((HeadunitUiCarouselItem item) => item.toJson())
        .toList(growable: false),
  };

  @override
  Iterable<HeadunitUiAction> get actions =>
      items.map((HeadunitUiCarouselItem item) => item.action);
}

class HeadunitUiListItem {
  final String id;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final int? iconCodePoint;
  final HeadunitUiAction? action;

  HeadunitUiListItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.iconCodePoint,
    this.action,
  }) {
    _validateIdentifier(id, 'list item id');
    _validateText(title, 'title', maxLength: 160);
    if (subtitle != null) _validateText(subtitle!, 'subtitle', maxLength: 240);
    if (trailingText != null) {
      _validateText(trailingText!, 'trailingText', maxLength: 80);
    }
    if (iconCodePoint != null &&
        (iconCodePoint! < 0 || iconCodePoint! > 0x10ffff)) {
      throw ArgumentError.value(iconCodePoint, 'iconCodePoint');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (trailingText != null) 'trailingText': trailingText,
    if (iconCodePoint != null) 'iconCodePoint': iconCodePoint,
    if (action != null) 'action': action!.toJson(),
  };
}

class HeadunitUiList extends HeadunitUiComponent {
  final List<HeadunitUiListItem> items;

  HeadunitUiList({required List<HeadunitUiListItem> items})
    : items = List<HeadunitUiListItem>.unmodifiable(items) {
    if (items.isEmpty || items.length > 48) {
      throw ArgumentError.value(
        items.length,
        'items',
        'Expected 1..48 list items.',
      );
    }
    if (items.map((HeadunitUiListItem item) => item.id).toSet().length !=
        items.length) {
      throw ArgumentError.value(
        items,
        'items',
        'List item IDs must be unique.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'list',
    'items': items
        .map((HeadunitUiListItem item) => item.toJson())
        .toList(growable: false),
  };

  @override
  Iterable<HeadunitUiAction> get actions sync* {
    for (final HeadunitUiListItem item in items) {
      if (item.action != null) yield item.action!;
    }
  }
}

class HeadunitUiMediaControls extends HeadunitUiComponent {
  final String title;
  final String? artist;
  final bool isPlaying;
  final HeadunitUiAction? previousAction;
  final HeadunitUiAction? playPauseAction;
  final HeadunitUiAction? nextAction;
  final double? progress;

  HeadunitUiMediaControls({
    required this.title,
    this.artist,
    required this.isPlaying,
    this.previousAction,
    this.playPauseAction,
    this.nextAction,
    this.progress,
  }) {
    _validateText(title, 'title', maxLength: 160);
    if (artist != null) _validateText(artist!, 'artist', maxLength: 160);
    if (progress != null &&
        (!progress!.isFinite || progress! < 0 || progress! > 1)) {
      throw ArgumentError.value(progress, 'progress');
    }
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'mediaControls',
    'title': title,
    if (artist != null) 'artist': artist,
    'isPlaying': isPlaying,
    if (previousAction != null) 'previousAction': previousAction!.toJson(),
    if (playPauseAction != null) 'playPauseAction': playPauseAction!.toJson(),
    if (nextAction != null) 'nextAction': nextAction!.toJson(),
    if (progress != null) 'progress': progress,
  };

  @override
  Iterable<HeadunitUiAction> get actions sync* {
    if (previousAction != null) yield previousAction!;
    if (playPauseAction != null) yield playPauseAction!;
    if (nextAction != null) yield nextAction!;
  }
}

class HeadunitUiProgress extends HeadunitUiComponent {
  final double value;
  final String? label;

  HeadunitUiProgress({required this.value, this.label}) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, 'value');
    }
    if (label != null) _validateText(label!, 'label', maxLength: 120);
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'progress',
    'value': value,
    if (label != null) 'label': label,
  };

  @override
  Iterable<HeadunitUiAction> get actions => const <HeadunitUiAction>[];
}

List<HeadunitUiComponent> _readComponents(Object? value, {required int depth}) {
  if (value is! List || value.isEmpty || value.length > 32) {
    throw const FormatException('Component children must contain 1..32 items.');
  }
  return value
      .map((Object? item) => HeadunitUiComponent.fromJson(item, depth: depth))
      .toList(growable: false);
}

List<HeadunitUiCarouselItem> _readCarouselItems(Object? value) {
  if (value is! List || value.isEmpty || value.length > 24) {
    throw const FormatException('Carousel items must contain 1..24 items.');
  }
  return value
      .map((Object? raw) {
        final Map<String, Object?> json = _readMap(raw, 'carousel item');
        return HeadunitUiCarouselItem(
          id: _readString(json, 'id'),
          title: _readString(json, 'title'),
          subtitle: _readOptionalString(json, 'subtitle'),
          imageUrl: _readOptionalImageUrl(json, 'imageUrl'),
          action: HeadunitUiAction.fromJson(json['action']),
        );
      })
      .toList(growable: false);
}

List<HeadunitUiListItem> _readListItems(Object? value) {
  if (value is! List || value.isEmpty || value.length > 48) {
    throw const FormatException('List items must contain 1..48 items.');
  }
  return value
      .map((Object? raw) {
        final Map<String, Object?> json = _readMap(raw, 'list item');
        return HeadunitUiListItem(
          id: _readString(json, 'id'),
          title: _readString(json, 'title'),
          subtitle: _readOptionalString(json, 'subtitle'),
          trailingText: _readOptionalString(json, 'trailingText'),
          iconCodePoint: _readOptionalInt(
            json,
            'iconCodePoint',
            min: 0,
            max: 0x10ffff,
          ),
          action: _readOptionalAction(json, 'action'),
        );
      })
      .toList(growable: false);
}

HeadunitUiAction? _readOptionalAction(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  return value == null ? null : HeadunitUiAction.fromJson(value);
}

Map<String, Object?> _readMap(Object? value, String description) {
  if (value is! Map) {
    throw FormatException('Expected $description to be an object.');
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Object keys must be strings.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _readString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Field "$key" must be a non-empty string.');
  }
  return value;
}

String? _readOptionalString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value != null && value is! String) {
    throw FormatException('Field "$key" must be a string.');
  }
  return value as String?;
}

bool _readBool(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! bool) throw FormatException('Field "$key" must be a boolean.');
  return value;
}

num _readNumber(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! num || !value.isFinite) {
    throw FormatException('Field "$key" must be a finite number.');
  }
  return value;
}

num? _readOptionalNumber(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value != null && (value is! num || !value.isFinite)) {
    throw FormatException('Field "$key" must be a finite number.');
  }
  return value as num?;
}

int? _readOptionalInt(
  Map<String, Object?> json,
  String key, {
  required int min,
  required int max,
}) {
  final Object? value = json[key];
  if (value == null) return null;
  if (value is! int || value < min || value > max) {
    throw FormatException('Field "$key" is outside its allowed range.');
  }
  return value;
}

T _readEnum<T extends Enum>(
  List<T> values,
  Object? raw,
  String description, {
  required T defaultValue,
}) {
  if (raw == null) return defaultValue;
  if (raw is! String) throw FormatException('$description must be a string.');
  for (final T value in values) {
    if (value.name == raw) return value;
  }
  throw FormatException('Unknown $description: $raw.');
}

String? _readOptionalImageUrl(Map<String, Object?> json, String key) {
  final String? value = _readOptionalString(json, key);
  if (value != null) _validateImageUrl(value);
  return value;
}

void _validateIdentifier(String value, String name) {
  if (value.isEmpty || value.length > 96 || value.trim() != value) {
    throw ArgumentError.value(
      value,
      name,
      'Must contain 1..96 non-whitespace-edge characters.',
    );
  }
}

void _validateText(String value, String name, {required int maxLength}) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Text must not be empty.');
  }
  if (value.length > maxLength) {
    throw ArgumentError.value(value, name, 'Text is too long.');
  }
}

void _validateImageUrl(String value) {
  if (value.length > 2048) {
    throw ArgumentError.value(value, 'url', 'URL is too long.');
  }
  final Uri? uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    throw ArgumentError.value(
      value,
      'url',
      'Only absolute HTTP(S) image URLs are supported.',
    );
  }
}
