part of 'audio_service.dart';

class AudioStream {
  static final Logger _log = Logger('AudioStream');

  final AudioStreamId id;
  final AudioStreamConfiguration configuration;

  final SoLoud _soLoud;

  late final AudioSource _nativeStream;

  SoundHandle? _handle;

  bool _disposed = false;
  bool _ended = false;

  AudioStream._({
    required this.id,
    required this.configuration,
    required SoLoud soLoud,
  }) : _soLoud = soLoud {
    _nativeStream = _soLoud.setBufferStream(
      bufferingType: BufferingType.released,
      channels: _mapChannels(configuration.channels),
      sampleRate: configuration.sampleRate,
      format: _mapFormat(configuration.format),
    );
  }

  bool get isDisposed => _disposed;

  bool get isPlaying {
    final SoundHandle? handle = _handle;

    return !_disposed &&
        handle != null &&
        _soLoud.getIsValidVoiceHandle(handle);
  }

  void play() {
    _ensureNotDisposed();

    if (_ended) {
      throw StateError('Cannot play a finished audio stream.');
    }

    if (isPlaying) {
      _log.warning('AudioStream $id is already playing.');
      return;
    }

    _handle = _soLoud.play(_nativeStream);
  }

  void pause() {
    final SoundHandle? handle = _getActiveHandle();

    if (handle == null) {
      _log.warning('Cannot pause AudioStream $id: it is not playing.');
      return;
    }

    _soLoud.setPause(handle, true);
  }

  void resume() {
    final SoundHandle? handle = _getActiveHandle();

    if (handle == null) {
      _log.warning('Cannot resume AudioStream $id: it is not playing.');
      return;
    }

    _soLoud.setPause(handle, false);
  }

  void appendData(Uint8List bytes) {
    _ensureNotDisposed();

    if (_ended) {
      throw StateError('Cannot append data to a finished audio stream.');
    }

    if (bytes.isEmpty) {
      return;
    }

    _soLoud.addAudioDataStream(_nativeStream, bytes);
  }

  void finish() {
    _ensureNotDisposed();

    if (_ended) {
      return;
    }

    _soLoud.setDataIsEnded(_nativeStream);
    _ended = true;
  }

  Future<void> stop() async {
    if (_disposed) {
      return;
    }

    final SoundHandle? handle = _getActiveHandle();

    if (handle == null) {
      return;
    }

    await _soLoud.stop(handle);

    _handle = null;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    final SoundHandle? handle = _handle;
    _handle = null;

    try {
      if (handle != null &&
          _soLoud.getIsValidVoiceHandle(handle)) {
        await _soLoud.stop(handle);
      }
    } finally {
      await _soLoud.disposeSource(_nativeStream);
    }
  }

  SoundHandle? _getActiveHandle() {
    _ensureNotDisposed();

    final SoundHandle? handle = _handle;

    if (handle == null ||
        !_soLoud.getIsValidVoiceHandle(handle)) {
      _handle = null;
      return null;
    }

    return handle;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('AudioStream $id has been disposed.');
    }
  }

  static Channels _mapChannels(AudioChannelLayout channels) {
    return switch (channels) {
      AudioChannelLayout.mono => Channels.mono,
      AudioChannelLayout.stereo => Channels.stereo,
      AudioChannelLayout.quad => Channels.quad,
      AudioChannelLayout.surround51 => Channels.surround51,
      AudioChannelLayout.dolby71 => Channels.dolby71,
    };
  }

  static BufferType _mapFormat(AudioSampleFormat format) {
    return switch (format) {
      AudioSampleFormat.signed8 => BufferType.s8,
      AudioSampleFormat.signed16LittleEndian => BufferType.s16le,
      AudioSampleFormat.signed32LittleEndian => BufferType.s32le,
      AudioSampleFormat.float32LittleEndian => BufferType.f32le,
    };
  }
}