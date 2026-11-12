final class ServiceId {
  static final RegExp _pattern = RegExp(
    r'^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:\.[a-z0-9]+(?:[._-][a-z0-9]+)*)+$',
  );

  final String value;

  ServiceId(this.value) {
    if (value != value.trim() || !_pattern.hasMatch(value)) {
      throw ArgumentError.value(value, 'value', 'Invalid service identifier.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ServiceId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
