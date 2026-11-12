enum ApplicationBackgroundPolicy {
  keepMounted('keepMounted'),
  suspend('suspend'),
  stop('stop');

  const ApplicationBackgroundPolicy(this.wireName);

  final String wireName;

  static ApplicationBackgroundPolicy fromWireName(String value) {
    for (final ApplicationBackgroundPolicy policy in values) {
      if (policy.wireName == value) {
        return policy;
      }
    }

    throw FormatException(
      'Unsupported application background policy: $value',
    );
  }
}