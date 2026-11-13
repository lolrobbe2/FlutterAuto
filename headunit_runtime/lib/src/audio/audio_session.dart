part of 'audio_service.dart';

class AudioSession {
  final AudioSessionId id;
  final SoLoud _soLoud;

  final Map<AudioStreamId, AudioStream> _streams = {};

  bool _closed = false;

  AudioSession._({required this.id, required this._soLoud});

  bool get isClosed => _closed;

  Map<AudioStreamId, AudioStream> get streams =>
      Map<AudioStreamId, AudioStream>.unmodifiable(_streams);

  AudioStream createStream({
    required AudioStreamId id,
    required AudioStreamConfiguration configuration,
  }) {
    if (_closed) {
      throw StateError('AudioSession $id is closed.');
    }

    if (_streams.containsKey(id)) {
      throw StateError('AudioStream $id already exists in session ${this.id}.');
    }

    final AudioStream stream = AudioStream._(
      id: id,
      configuration: configuration,
      soLoud: _soLoud,
    );

    _streams[id] = stream;

    return stream;
  }

  AudioStream? getStream(AudioStreamId id) {
    return _streams[id];
  }

  Future<void> removeStream(AudioStreamId id) async {
    final AudioStream? stream = _streams.remove(id);

    if (stream == null) {
      return;
    }

    await stream.dispose();
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;

    final List<AudioStream> streamsToClose = _streams.values.toList();

    _streams.clear();

    await Future.wait(
      streamsToClose.map((AudioStream stream) => stream.dispose()),
    );
  }
}
