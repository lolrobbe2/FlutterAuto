final class ModuleId {
  static final RegExp _pattern = RegExp(
    r'^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:\.[a-z0-9]+(?:[._-][a-z0-9]+)*)+$',
  );

  final String value;

  ModuleId(this.value) {
    if (value != value.trim() || !_pattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'Module ID must use lowercase reverse-DNS notation.',
      );
    }
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ModuleId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
