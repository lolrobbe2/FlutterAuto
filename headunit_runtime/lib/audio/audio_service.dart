import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:logging/logging.dart';

part 'audio_session.dart';
part 'audio_stream.dart';

class AudioService {
  static final Logger _log = Logger('AudioService');

  final Map<AudioSessionId, AudioSession> _sessions = {};

  int _nextSessionId = 1;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Map<AudioSessionId, AudioSession> get sessions =>
      Map<AudioSessionId, AudioSession>.unmodifiable(_sessions);

  Future<bool> initialize() async {
    if (_initialized) {
      return true;
    }

    try {
      if (!SoLoud.instance.isInitialized) {
        await SoLoud.instance.init();
      }

      _initialized = true;
      _log.info('Audio service initialized.');

      return true;
    } catch (error, stackTrace) {
      if (error is SoLoudNoPlaybackDevicesFoundCppException) {
        _log.severe(
          'No playback devices found.',
          error,
          stackTrace,
        );
      } else {
        _log.severe(
          'Failed to initialize audio service.',
          error,
          stackTrace,
        );
      }

      return false;
    }
  }

  AudioSession createSession() {
    if (!_initialized) {
      throw StateError('AudioService is not initialized.');
    }

    final AudioSessionId id = AudioSessionId(_nextSessionId++);

    final AudioSession session = AudioSession._(
      id: id,
      soLoud: SoLoud.instance,
    );

    _sessions[id] = session;

    _log.info('Created audio session $id.');

    return session;
  }

  AudioSession? getSession(AudioSessionId id) {
    return _sessions[id];
  }

  Future<void> removeSession(AudioSessionId id) async {
    final AudioSession? session = _sessions.remove(id);

    if (session == null) {
      return;
    }

    await session.close();

    _log.info('Removed audio session $id.');
  }

  Future<void> dispose() async {
    final List<AudioSession> sessionsToClose =
        _sessions.values.toList();

    _sessions.clear();

    try {
      await Future.wait(
        sessionsToClose.map(
          (AudioSession session) => session.close(),
        ),
      );
    } finally {
      if (_initialized && SoLoud.instance.isInitialized) {
        await SoLoud.instance.deinitAsync();
      }

      _initialized = false;

      _log.info('Audio service disposed.');
    }
  }
}