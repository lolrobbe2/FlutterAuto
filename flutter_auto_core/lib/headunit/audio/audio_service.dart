import 'package:flutter_auto_core/headunit/audio/audio_stream.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logging/logging.dart';

class AudioService {
  static final Logger _log = Logger('AndroidAutoTlsClient');
  static final bool _initialized = false;
  static final Map<int, AudioStream> streams = {};

  /// This function initializes the internal [SoLoud] backend.
  static Future<bool> initialize() async {
    if (_initialized) {
      //TODO reset audio ?!
      return true;
    }
    try {
      await SoLoud.instance.init();
    } catch (error) {
      if(error is SoLoudNoPlaybackDevicesFoundCppException){
        _log.severe("No playback devices found");
      }
      return false;
    }
    return true;
  }

  static AudioStream createStream(int session, Channels channels, BufferType type, int sampleRate){
    AudioStream stream =  AudioStream(channels, type, sampleRate);
    streams[session] = stream;
    return streams[session]!;
  }
}
