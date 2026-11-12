import 'audio_session_id.dart';
import 'audio_stream.dart';
import 'audio_stream_id.dart';
import 'audio_stream_configuration.dart';

abstract interface class AudioSession {
  AudioSessionId get id;

  bool get isClosed;

  Map<AudioStreamId, AudioStream> get streams;

  AudioStream createStream({
    required AudioStreamId id,
    required AudioStreamConfiguration configuration,
  });

  AudioStream? getStream(AudioStreamId id);

  Future<void> removeStream(AudioStreamId id);

  Future<void> close();
}