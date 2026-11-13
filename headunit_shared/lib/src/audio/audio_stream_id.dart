final class AudioStreamId {
  final int value;

  const AudioStreamId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AudioStreamId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value.toString();
}
