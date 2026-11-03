import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logging/logging.dart';

class AudioService {
  static final Logger _log = Logger('AndroidAutoTlsClient');
  static bool _initialized = false;
  /**
   * This function initializes the internal [SoLoud] backend.
   */
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
}
