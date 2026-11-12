final class CapabilityId {
  static final RegExp _pattern = RegExp(
    r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+$',
  );

  final String value;

  CapabilityId(this.value) {
    if (value != value.trim() || !_pattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'Invalid capability identifier.',
      );
    }
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CapabilityId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}