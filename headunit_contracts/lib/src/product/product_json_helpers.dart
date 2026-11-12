Map<String, Object?> productReadObject(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('$field must be an object.');
  }

  final Map<String, Object?> result = <String, Object?>{};

  for (final Object? key in value.keys) {
    if (key is! String) {
      throw FormatException('$field contains a non-string key.');
    }

    result[key] = value[key];
  }

  return result;
}

String productReadRequiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];

  if (value is! String || value.isEmpty) {
    throw FormatException('Missing or invalid field: $key');
  }

  return value;
}

bool productReadOptionalBool(
  Map<String, Object?> json,
  String key, {
  required bool defaultValue,
}) {
  if (!json.containsKey(key)) {
    return defaultValue;
  }

  final Object? value = json[key];

  if (value is! bool) {
    throw FormatException('Invalid field: $key');
  }

  return value;
}

List<Object?> productReadOptionalList(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    return <Object?>[];
  }

  final Object? value = json[key];

  if (value is! List) {
    throw FormatException('$key must be a list.');
  }

  return List<Object?>.from(value);
}
