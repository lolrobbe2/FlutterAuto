
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter_auto/headunit/service/video_service.dart';
import 'package:logging/logging.dart';

class FfmpegH264Decoder {
  FfmpegH264Decoder({
    this.width = 800,
    this.height = 480,
  })  : assert(width > 0),
        assert(height > 0);

  final int width;
  final int height;

  final Logger _log = Logger('FfmpegH264Decoder');

  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();

  final StreamController<String> _errors =
      StreamController<String>.broadcast();

  Stream<Uint8List> get frames => _frames.stream;
  Stream<String> get errors => _errors.stream;

  final Queue<Uint8List> _pendingPackets = Queue<Uint8List>();

  static const int _maxPendingBytes = 8 * 1024 * 1024;

  int _pendingBytes = 0;
  int? _sessionId;
  int _frameOffset = 0;

  bool _disposed = false;

  Future<void>? _startFuture;
  Completer<void>? _ffmpegFinished;

  ServerSocket? _outputServer;
  StreamSubscription<Socket>? _outputServerSubscription;
  Socket? _outputSocket;
  StreamSubscription<List<int>>? _outputSubscription;
  Socket? _inputSocket;
  StreamSubscription<VideoMediaPacket>? _packetSubscription;

  late Uint8List _frameBuffer;

  int get _frameSize => width * height * 4;

  Future<void> start(VideoService service) {
    if (_disposed) {
      throw StateError('The decoder has been disposed.');
    }

    return _startFuture ??= _startInternal(service);
  }

  Future<void> _startInternal(VideoService service) async {
    _frameBuffer = Uint8List(_frameSize);
    _ffmpegFinished = Completer<void>();

    // Subscribe first so packets arriving during startup aren't lost.
    _packetSubscription = service.videoPackets.listen(
      _handlePacket,
      onError: (Object error, StackTrace stackTrace) {
        _reportError('Video packet stream failed: $error');
      },
    );

    try {
      final outputServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );

      _outputServer = outputServer;

      // Start accepting FFmpeg's decoded rawvideo connection before
      // launching FFmpeg.
      _outputServerSubscription = outputServer.listen(_acceptOutputSocket);

      final inputPort = await _reservePort();

      final inputUrl =
          'tcp://127.0.0.1:$inputPort?listen=1';
      final outputUrl =
          'tcp://127.0.0.1:${outputServer.port}';

      final arguments = <String>[
        '-hide_banner',
        '-loglevel', 'warning',
        '-f', 'h264',
        '-i', inputUrl,
        '-an',
        '-sn',
        '-dn',
        '-vf', 'scale=$width:$height',
        '-pix_fmt', 'rgba',
        '-c:v', 'rawvideo',
        '-f', 'rawvideo',
        '-flush_packets', '1',
        outputUrl,
      ];

      _log.info(
        'Starting bundled FFmpeg for ${width}x$height H.264.',
      );

      // FFmpeg runs inside the plugin, not through a system executable.
      final session = await FFmpegKit.executeWithArgumentsAsync(
        arguments,
        (completedSession) async {
          try {
            final code = await completedSession.getReturnCode();

            if (!_disposed && !ReturnCode.isSuccess(code)) {
              final logs = await completedSession.getLogsAsString();
              _reportError(
                'FFmpeg exited unsuccessfully ($code). '
                '${logs}',
              );
            }
          } catch (error) {
            if (!_disposed) {
              _reportError('Could not read FFmpeg result: $error');
            }
          } finally {
            final finished = _ffmpegFinished;
            if (finished != null && !finished.isCompleted) {
              finished.complete();
            }
          }
        },
        (log) {
          final text = log.getMessage().trim();
          if (text.isNotEmpty) {
            _log.fine('FFmpeg: $text');
          }
        },
      );

      _sessionId = session.getSessionId();

      if (_disposed) {
        await FFmpegKit.cancel(_sessionId);
        return;
      }

      // FFmpeg listens for its raw H.264 input. Retry while the
      // native command opens its listening socket.
      _inputSocket = await _connectWithRetry(inputPort);

      while (_pendingPackets.isNotEmpty) {
        final packet = _pendingPackets.removeFirst();
        _pendingBytes -= packet.length;
        _inputSocket!.add(packet);
      }

      await _inputSocket!.flush();

      _log.info('FFmpeg input connected; decoder is ready.');
    } catch (error) {
      final sessionId = _sessionId;

      if (sessionId != null) {
        try {
          await FFmpegKit.cancel(sessionId);
        } catch (_) {
          // Preserve the original startup error.
        }
      }

      _reportError('Failed to start FFmpeg decoder: $error');
      rethrow;
    }
  }

  Future<int> _reservePort() async {
    // Reserve an ephemeral port, then release it for FFmpeg's TCP listener.
    final probe = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );

    final port = probe.port;
    await probe.close();

    return port;
  }

  Future<Socket> _connectWithRetry(int port) async {
    final deadline = DateTime.now().add(
      const Duration(seconds: 10),
    );

    Object? lastError;

    while (!_disposed && DateTime.now().isBefore(deadline)) {
      try {
        return await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 400),
        );
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(
          const Duration(milliseconds: 100),
        );
      }
    }

    throw StateError(
      'Could not connect to FFmpeg input on port $port: $lastError',
    );
  }

  void _acceptOutputSocket(Socket socket) {
    if (_disposed || _outputSocket != null) {
      socket.destroy();
      return;
    }

    _outputSocket = socket;

    _outputSubscription = socket.listen(
      _handleDecodedBytes,
      onError: (Object error, StackTrace stackTrace) {
        if (!_disposed) {
          _reportError('FFmpeg output socket failed: $error');
        }
      },
      onDone: () {
        if (!_disposed) {
          _log.info('FFmpeg output stream closed.');
        }
      },
      cancelOnError: true,
    );

    _log.info('Connected to FFmpeg decoded-video output.');
  }

  void _handlePacket(VideoMediaPacket packet) {
    if (_disposed) return;

    var data = packet.payload;

    // The timestamped media variant carries an eight-byte timestamp
    // before its H.264 payload.
    if (packet.messageId == 0x0000) {
      if (data.length <= 8) return;
      data = Uint8List.sublistView(data, 8);
    }

    if (data.isEmpty) return;

    final inputSocket = _inputSocket;

    if (inputSocket != null) {
      try {
        inputSocket.add(data);
      } catch (error) {
        _reportError('Could not write H.264 data to FFmpeg: $error');
      }
      return;
    }

    // Bound memory while FFmpeg starts. Oldest packets are dropped if
    // startup takes too long; normal operation writes directly to TCP.
    final copy = Uint8List.fromList(data);

    while (_pendingPackets.isNotEmpty &&
        _pendingBytes + copy.length > _maxPendingBytes) {
      _pendingBytes -= _pendingPackets.removeFirst().length;
    }

    if (copy.length > _maxPendingBytes) {
      _log.warning('Dropping oversized startup video packet.');
      return;
    }

    _pendingPackets.add(copy);
    _pendingBytes += copy.length;
  }

  void _handleDecodedBytes(List<int> bytes) {
    if (_disposed || bytes.isEmpty) return;

    var sourceOffset = 0;

    // TCP chunks have no frame boundaries, so reconstruct RGBA frames
    // using the negotiated output dimensions.
    while (sourceOffset < bytes.length) {
      final available = _frameSize - _frameOffset;
      final count = math.min(
        available,
        bytes.length - sourceOffset,
      );

      _frameBuffer.setRange(
        _frameOffset,
        _frameOffset + count,
        bytes,
        sourceOffset,
      );

      _frameOffset += count;
      sourceOffset += count;

      if (_frameOffset == _frameSize) {
        _frames.add(Uint8List.fromList(_frameBuffer));
        _frameOffset = 0;
      }
    }
  }

  void _reportError(String message) {
    _log.severe(message);

    if (!_disposed && !_errors.isClosed) {
      _errors.add(message);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _packetSubscription?.cancel();

    try {
      await _inputSocket?.flush();
      await _inputSocket?.close();
    } catch (_) {
      // Socket may already be closed.
    }

    // Closing input normally lets FFmpeg finish. Cancel only this
    // decoder's session if it does not exit promptly.
    final finished = _ffmpegFinished;

    if (finished != null && !finished.isCompleted) {
      try {
        await finished.future.timeout(
          const Duration(seconds: 2),
        );
      } on TimeoutException {
        final sessionId = _sessionId;
        if (sessionId != null) {
          await FFmpegKit.cancel(sessionId);
        }
      }
    }

    await _outputSubscription?.cancel();
    await _outputServerSubscription?.cancel();

    _inputSocket?.destroy();
    _outputSocket?.destroy();

    try {
      await _outputServer?.close();
    } catch (_) {
      // Already closed.
    }

    _pendingPackets.clear();
    _pendingBytes = 0;

    await _frames.close();
    await _errors.close();
  }
}
