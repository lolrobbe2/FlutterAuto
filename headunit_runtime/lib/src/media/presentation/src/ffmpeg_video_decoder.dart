import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:headunit_shared/headunit_shared_io.dart'
    show EncodedVideoFrame, VideoCodec, VideoStreamConfiguration;

import 'video_decoder.dart';

/// FFmpegKit-backed decoder for the headunit's single foreground remote app.
///
/// The authenticated FlutterAuto media connection remains the source of the
/// video. This class forwards raw H.264/H.265 Annex-B access units into an
/// ephemeral loopback TCP listener which FFplay reads using FFmpeg's built-in
/// TCP protocol. The listener is bound only to 127.0.0.1.
///
/// FFplayKit owns decoding and the Flutter output surface. FlutterAuto does not
/// implement or maintain platform-native decoder code.
class FfmpegVideoDecoder implements VideoDecoder, StartableVideoDecoder {
  FfmpegVideoDecoder._({
    required this._surface,
    required ServerSocket this._server,
    required this._configuration,
  });

  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _stopTimeout = Duration(seconds: 3);

  // FFplayKit exposes one process-wide current playback-control owner. The
  // headunit shell currently displays one foreground external application.
  static bool _decoderInUse = false;

  final FFplaySurface _surface;
  final VideoStreamConfiguration _configuration;
  ServerSocket? _server;
  FFplaySession? _session;
  Socket? _inputSocket;
  _PlaybackState? _playbackState;
  final Completer<void> _disposeSignal = Completer<void>();

  bool _disposed = false;
  bool _started = false;
  bool _awaitingKeyFrame = true;
  int? _lastSequenceNumber;
  Future<void>? _startFuture;
  Future<void>? _disposeFuture;
  Future<void> _decodeTail = Future<void>.value();

  /// Creates the Flutter output surface and local input listener.
  ///
  /// Playback is intentionally not started here. [start] is called by
  /// [RemoteVideoSurface] only after [buildView] has been mounted. The
  /// consuming application must include an FFmpegKit video bundle. For
  /// embedded production builds, deploy a custom minimal FFmpegKit artifact;
  /// the stock video bundle is too large for most constrained devices.
  static Future<FfmpegVideoDecoder> create(
    VideoStreamConfiguration configuration,
  ) async {
    configuration.validate();
    if (_decoderInUse) {
      throw StateError(
        'FlutterAuto supports one foreground remote video surface per process.',
      );
    }
    _decoderInUse = true;

    FFplaySurface? surface;
    ServerSocket? server;
    try {
      // Initialization is idempotent and intentionally lazy: headunits which
      // never launch external apps do not initialize the FFmpeg runtime.
      await FFmpegKitExtended.initialize();
      if (FFplayKit.currentSession != null) {
        throw StateError(
          'FFplayKit already has an active playback session in this process.',
        );
      }

      surface = await FFplaySurface.create(
        width: configuration.width,
        height: configuration.height,
      );
      if (surface == null) {
        throw UnsupportedError(
          'FFmpegKit did not provide a video surface for this platform.',
        );
      }

      // Loopback TCP provides the same input protocol on Windows and Android
      // without making FlutterAuto depend on OS-specific named pipes.
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

      final FfmpegVideoDecoder decoder = FfmpegVideoDecoder._(
        surface: surface,
        server: server,
        configuration: configuration,
      );
      surface = null;
      server = null;
      return decoder;
    } catch (_) {
      if (server != null) {
        await server.close();
      }
      if (surface != null) {
        try {
          await surface.release();
        } catch (_) {
          // Preserve the original initialization failure.
        }
      }
      _decoderInUse = false;
      rethrow;
    }
  }

  @override
  Widget buildView() => _surface.toWidget();

  @override
  Future<void> start() => _startFuture ??= _startCore();

  Future<void> _startCore() async {
    if (_disposed) {
      throw StateError('The FFmpeg video decoder has been disposed.');
    }
    if (_started) {
      return;
    }

    final ServerSocket server =
        _server ??
        (throw StateError('The FFmpeg video input listener is unavailable.'));
    final Future<Socket> incomingSocket = server.first.timeout(
      _connectTimeout,
      onTimeout: () {
        throw TimeoutException(
          'FFplay did not connect to its local video input.',
          _connectTimeout,
        );
      },
    );
    final Uri inputUri = Uri(
      scheme: 'tcp',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      queryParameters: const <String, String>{'tcp_nodelay': '1'},
    );
    final List<String> arguments = buildPlayerArguments(
      _configuration,
      inputUri,
    );
    final _PlaybackState playbackState = _PlaybackState();
    _playbackState = playbackState;

    try {
      final FFplaySession session = await FFplayKit.executeAsync(
        arguments.join(' '),
        onComplete: playbackState.complete,
        onLog: (log) => playbackState.addLog(log.message),
      );
      _session = session;

      if (_disposed) {
        throw StateError(
          'The FFmpeg video decoder was disposed during startup.',
        );
      }

      // Fail immediately if FFplay exits during startup instead of waiting for
      // the socket timeout. Disposal also wins this race so surface teardown
      // cannot leave the decoder waiting for a connection.
      final Socket socket = await Future.any<Socket>(<Future<Socket>>[
        incomingSocket,
        playbackState.completed.future.then<Socket>((_) {
          final String? failure = playbackState.failure;
          throw StateError(
            failure == null
                ? 'FFplay stopped before opening its local video input.'
                : 'FFplay failed during startup: $failure',
          );
        }),
        _disposeSignal.future.then<Socket>((_) {
          throw StateError(
            'The FFmpeg video decoder was disposed during startup.',
          );
        }),
      ]);

      if (_disposed) {
        socket.destroy();
        throw StateError(
          'The FFmpeg video decoder was disposed during startup.',
        );
      }

      await server.close();
      _server = null;
      socket.setOption(SocketOption.tcpNoDelay, true);
      _inputSocket = socket;
      _started = true;
    } catch (_) {
      await _closePlaybackResources();
      rethrow;
    }
  }

  /// Builds FFplay arguments without loading the native FFmpeg runtime.
  @visibleForTesting
  static List<String> buildPlayerArguments(
    VideoStreamConfiguration configuration,
    Uri inputUri,
  ) {
    configuration.validate();
    if (inputUri.scheme != 'tcp' || inputUri.host != '127.0.0.1') {
      throw ArgumentError.value(
        inputUri,
        'inputUri',
        'The FFplay bridge must use loopback TCP.',
      );
    }

    final String demuxer = switch (configuration.codec) {
      VideoCodec.h264 => 'h264',
      VideoCodec.h265 => 'hevc',
    };
    final List<String> arguments = <String>[
      '-hide_banner',
      '-loglevel',
      'info',
      '-fflags',
      'nobuffer',
      '-flags',
      'low_delay',

      // Do not enable -hwaccel here.
      // FFplay automatically switches to Vulkan when this option is enabled.
      // Windows FFplayDesktopTexture uses the SDL2 rendering path.
      '-f',
      demuxer,
      // Raw H.264/HEVC does not carry a reliable presentation time base.
      // Apply the configured input frame rate before opening the demuxer.
      '-r',
      configuration.framesPerSecond.toString(),
      '-i',
      inputUri.toString(),
      '-an',
      '-sn',
      '-dn',
      '-sync',
      'video',
      '-framedrop',
    ];
    final String? rotationFilter = switch (configuration.rotationDegrees) {
      0 => null,
      90 => 'transpose=clock',
      180 => 'hflip,vflip',
      270 => 'transpose=cclock',
      _ => throw ArgumentError.value(
        configuration.rotationDegrees,
        'rotationDegrees',
      ),
    };
    if (rotationFilter != null) {
      arguments.addAll(<String>['-vf', rotationFilter]);
    }
    return arguments;
  }

  @override
  Future<void> decode(EncodedVideoFrame frame) {
    final Future<void> operation = _decodeTail.then((_) => _decodeFrame(frame));
    // Keep the queue usable after an individual write fails, while returning
    // the original error to the caller that submitted that frame.
    _decodeTail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  Future<void> _decodeFrame(EncodedVideoFrame frame) async {
    if (_disposed) {
      throw StateError('The FFmpeg video decoder has been disposed.');
    }
    if (!_started || _inputSocket == null) {
      throw StateError('The FFmpeg video decoder has not been started.');
    }

    final _PlaybackState? playbackState = _playbackState;
    if (playbackState?.failure != null) {
      throw StateError('FFplay failed: ${playbackState!.failure}');
    }
    if (playbackState?.ended ?? false) {
      throw StateError('FFplay stopped while the remote stream was active.');
    }

    // A late subscription or a bounded-queue drop can leave the stream in the
    // middle of a GOP. Do not feed dependent pictures until the next IDR/key
    // frame, which re-establishes decoder references.
    final int? previousSequenceNumber = _lastSequenceNumber;
    if (previousSequenceNumber != null &&
        frame.sequenceNumber != previousSequenceNumber + 1) {
      _awaitingKeyFrame = true;
    }
    _lastSequenceNumber = frame.sequenceNumber;
    if (_awaitingKeyFrame) {
      if (!frame.isKeyFrame) {
        return;
      }
      _awaitingKeyFrame = false;
    }

    // Awaiting flush applies TCP backpressure. Combined with the media
    // subscription's bounded queue, this prevents unbounded Dart-side growth.
    final Socket inputSocket = _inputSocket!;
    inputSocket.add(frame.data);
    await inputSocket.flush();
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _disposeCore();

  Future<void> _disposeCore() async {
    _disposed = true;
    if (!_disposeSignal.isCompleted) {
      _disposeSignal.complete();
    }

    final Future<void>? startFuture = _startFuture;
    if (startFuture != null) {
      try {
        await startFuture.timeout(_stopTimeout);
      } catch (_) {
        // Startup failure or cancellation is handled by resource cleanup below.
      }
    }

    try {
      try {
        await _decodeTail.timeout(_stopTimeout);
      } catch (_) {
        // Continue teardown if a socket write cannot drain during shutdown.
      }
      await _closePlaybackResources();
      await _surface.release();
    } finally {
      _decoderInUse = false;
    }
  }

  Future<void> _closePlaybackResources() async {
    final Socket? inputSocket = _inputSocket;
    _inputSocket = null;
    inputSocket?.destroy();

    final ServerSocket? server = _server;
    _server = null;
    if (server != null) {
      await server.close();
    }

    final FFplaySession? session = _session;
    _session = null;
    if (session != null) {
      try {
        FFplayKit.cancel(session);
      } catch (_) {
        // Continue releasing the remaining playback resources.
      }
      final _PlaybackState? playbackState = _playbackState;
      if (playbackState != null) {
        try {
          await playbackState.completed.future.timeout(_stopTimeout);
        } catch (_) {
          // FFplay can already be terminal or may not acknowledge cancellation.
        }
      }
      try {
        session.close();
      } catch (_) {
        // The output surface must still be released.
      }
    }
  }
}

class _PlaybackState {
  final Completer<void> completed = Completer<void>();
  final List<String> _recentLogs = <String>[];

  bool ended = false;
  String? failure;

  void addLog(String message) {
    _recentLogs.add(message);

    // Keep diagnostics bounded for embedded devices.
    if (_recentLogs.length > 64) {
      _recentLogs.removeAt(0);
    }
  }

  void complete(FFplaySession session) {
    if (ended) {
      return;
    }

    ended = true;

    final int returnCode = session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final List<String> diagnostics = <String>[];

      final String? stackTrace = session.getFailStackTrace();
      if (stackTrace != null && stackTrace.isNotEmpty) {
        diagnostics.add(stackTrace);
      }

      final String? logs = session.getLogsAsString();
      if (logs != null && logs.isNotEmpty) {
        diagnostics.add(logs);
      }

      if (_recentLogs.isNotEmpty) {
        diagnostics.add('Recent FFplay logs:\n${_recentLogs.join('\n')}');
      }

      failure = diagnostics.isEmpty
          ? 'FFplay exited with return code $returnCode. '
                'Command: ${session.getCommand()}'
          : 'FFplay exited with return code $returnCode.\n'
                '${diagnostics.join('\n')}';
    }

    if (!completed.isCompleted) {
      completed.complete();
    }
  }
}
