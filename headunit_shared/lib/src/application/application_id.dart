final class ApplicationId {
  static final RegExp _pattern = RegExp(
    r'^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:\.[a-z0-9]+(?:[._-][a-z0-9]+)*)+$',
  );

  final String value;

  ApplicationId(this.value) {
    if (value != value.trim() || !_pattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'Application ID must use lowercase reverse-DNS notation.',
      );
    }
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ApplicationId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
