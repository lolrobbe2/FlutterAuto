enum AudioChannelLayout { mono, stereo, quad, surround51, dolby71 }

enum AudioSampleFormat {
  signed8,
  signed16LittleEndian,
  signed32LittleEndian,
  float32LittleEndian,
}

class AudioStreamConfiguration {
  final int sampleRate;
  final AudioChannelLayout channels;
  final AudioSampleFormat format;

  AudioStreamConfiguration({
    required this.sampleRate,
    required this.channels,
    required this.format,
  }) {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate');
    }
  }
}
