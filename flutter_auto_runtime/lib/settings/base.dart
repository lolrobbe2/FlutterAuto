abstract class SettingBase {
  const SettingBase({
    required this.key,
    required this.title,
    this.description,
    this.groupKey,
  });

  final String key;
  final String title;
  final String? description;
  final String? groupKey;

  Type get valueType;

  Object? get defaultValue;

  Object? encode(Object? value);

  Object? decode(Object? value);

  String? validate(Object? value);
}

class Setting<T> extends SettingBase {
  const Setting({
    required super.key,
    required super.title,
    required this.defaultValue,
    required this.fromJson,
    required this.toJson,
    super.description,
    super.groupKey,
    this.validator,
  });

  @override
  final T defaultValue;

  final T Function(Object? json) fromJson;
  final Object? Function(T value) toJson;
  final String? Function(T value)? validator;

  @override
  Type get valueType => T;

  @override
  Object? encode(Object? value) {
    return toJson(value as T);
  }

  @override
  Object? decode(Object? value) {
    return fromJson(value);
  }

  @override
  String? validate(Object? value) {
    if (value is! T) {
      return 'Expected $T, got ${value.runtimeType}';
    }

    return validator?.call(value);
  }
}
  