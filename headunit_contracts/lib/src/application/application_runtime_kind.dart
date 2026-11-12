enum ApplicationRuntimeKind {
  flutter('flutter'),
  web('web');

  const ApplicationRuntimeKind(this.wireName);

  final String wireName;

  static ApplicationRuntimeKind fromWireName(String value) {
    for (final ApplicationRuntimeKind kind in values) {
      if (kind.wireName == value) {
        return kind;
      }
    }

    throw FormatException(
      'Unsupported application runtime: $value',
    );
  }
}