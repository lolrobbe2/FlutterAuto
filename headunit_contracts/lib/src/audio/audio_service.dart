import 'audio_session.dart';
import 'audio_session_id.dart';

abstract interface class AudioService {
  bool get isInitialized;

  Map<AudioSessionId, AudioSession> get sessions;

  Future<void> initialize();

  AudioSession createSession();

  AudioSession? getSession(AudioSessionId id);

  Future<void> removeSession(AudioSessionId id);

  Future<void> dispose();
}