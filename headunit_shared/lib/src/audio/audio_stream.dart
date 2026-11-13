import 'dart:typed_data';

import 'audio_stream_id.dart';

abstract interface class AudioStream {
  AudioStreamId get id;

  void play();

  void pause();

  void resume();

  void appendData(Uint8List bytes);

  Future<void> stop();

  Future<void> dispose();
}
