import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logging/logging.dart';

class AudioStream {
  static final Logger _log = Logger('AndroidAutoTlsClient');

  // [SoLoud] local stream
  late AudioSource _nativeStream;
  SoundHandle? _handle;
  AudioStream(Channels channels, BufferType type, int sampleRate) {
    _nativeStream = SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
      channels: channels,
      sampleRate: sampleRate,
      format: type,
    );
  }
  void play() {
    if (_handle != null) {
      //a non null handle means we are already playing
      _log.warning("AudioStream was already playing");
      return;
    }
    _handle = SoLoud.instance.play(_nativeStream);
  }

  void pause() {
    if (_handle == null) {
      _log.severe("attempting to pause a not playing AudioStream");
      return;
    }
    SoLoud.instance.setPause(_handle!, true);
  }
  void appendData(Uint8List bytes){
    SoLoud.instance.addAudioDataStream(_nativeStream, bytes);
  }
}
