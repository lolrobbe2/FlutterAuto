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
class FfmpegVideoDecoder implements VideoDecoder {
  FfmpegVideoDecoder._({
    required this._surface,
    required this._session,
    required this._inputSocket,
    required this._playbackState,
  });

  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _stopTimeout = Duration(seconds: 3);

  // FFplayKit exposes one process-wide current playback-control owner. The
  // headunit shell currently displays one foreground external application.
  static bool _decoderInUse = false;

  final FFplaySurface _surface;
  final FFplaySession _session;
  final Socket _inputSocket;
  final _PlaybackState _playbackState;

  bool _disposed = false;
  bool _awaitingKeyFrame = true;
  int? _lastSequenceNumber;
  Future<void>? _disposeFuture;

  /// Creates an FFplay surface and starts a reader for the configured codec.
  ///
  /// The consuming application must include an FFmpegKit video bundle. For
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
    Socket? inputSocket;
    FFplaySession? session;
    _PlaybackState? playbackState;

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
        configuration,
        inputUri,
      );
      final String command = arguments.join(' ');

      final _PlaybackState activePlaybackState = _PlaybackState();
      playbackState = activePlaybackState;
      session = await FFplayKit.executeAsync(
        command,
        onComplete: activePlaybackState.complete,
      );

      // Fail immediately if FFplay exits during startup instead of waiting for
      // the socket timeout. This makes missing codecs/protocols visible as a
      // useful startup error and avoids a needless ten-second delay.
      inputSocket = await Future.any<Socket>(<Future<Socket>>[
        incomingSocket,
        activePlaybackState.completed.future.then<Socket>((_) {
          final String? failure = activePlaybackState.failure;
          throw StateError(
            failure == null
                ? 'FFplay stopped before opening its local video input.'
                : 'FFplay failed during startup: $failure',
          );
        }),
      ]);
      await server.close();
      server = null;
      inputSocket.setOption(SocketOption.tcpNoDelay, true);

      final FfmpegVideoDecoder decoder = FfmpegVideoDecoder._(
        surface: surface,
        session: session,
        inputSocket: inputSocket,
        playbackState: activePlaybackState,
      );

      // Ownership has moved into the decoder.
      surface = null;
      session = null;
      inputSocket = null;
      return decoder;
    } catch (_) {
      inputSocket?.destroy();
      if (server != null) {
        await server.close();
      }
      if (session != null) {
        try {
          FFplayKit.cancel(session);
        } catch (_) {
          // Preserve the original initialization failure.
        }
        if (playbackState != null) {
          try {
            await playbackState.completed.future.timeout(_stopTimeout);
          } catch (_) {
            // Preserve the original initialization failure.
          }
        }
        try {
          session.close();
        } catch (_) {
          // Preserve the original initialization failure.
        }
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
      'error',
      '-fflags',
      'nobuffer',
      '-flags',
      'low_delay',
      // FFplay's switch enables its hardware-accelerated video path and
      // Vulkan renderer. This is distinct from ffmpeg's `-hwaccel <backend>`
      // option; FFplay accepts this as a flag without a backend argument.
      '-hwaccel',
      '-f',
      demuxer,
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
  Widget buildView() => _surface.toWidget();

  @override
  Future<void> decode(EncodedVideoFrame frame) async {
    if (_disposed) {
      throw StateError('The FFmpeg video decoder has been disposed.');
    }
    if (_playbackState.failure != null) {
      throw StateError('FFplay failed: ${_playbackState.failure}');
    }
    if (_playbackState.ended) {
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
    _inputSocket.add(frame.data);
    await _inputSocket.flush();
  }

  @override
  Future<void> dispose() {
    return _disposeFuture ??= _disposeCore();
  }

  Future<void> _disposeCore() async {
    _disposed = true;
    try {
      _inputSocket.destroy();
      try {
        FFplayKit.cancel(_session);
      } catch (_) {
        // Continue releasing the remaining resources.
      }
      try {
        await _playbackState.completed.future.timeout(_stopTimeout);
      } catch (_) {
        // FFplay can already be terminal or may not acknowledge cancellation.
      }
      try {
        _session.close();
      } catch (_) {
        // The output surface must still be released.
      }
      await _surface.release();
    } finally {
      _decoderInUse = false;
    }
  }
}

class _PlaybackState {
  final Completer<void> completed = Completer<void>();
  bool ended = false;
  String? failure;

  void complete(FFplaySession session) {
    if (ended) {
      return;
    }
    ended = true;
    final int returnCode = session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final String? failStackTrace = session.getFailStackTrace();
      failure = failStackTrace == null || failStackTrace.isEmpty
          ? 'FFplay exited with return code $returnCode.'
          : failStackTrace;
    }
    if (!completed.isCompleted) {
      completed.complete();
    }
  }
}
