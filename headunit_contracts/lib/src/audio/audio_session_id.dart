final class AudioSessionId {
  final int value;

  const AudioSessionId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AudioSessionId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value.toString();
}
