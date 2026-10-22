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
  FfmpegH264Decoder({this.width = 800, this.height = 480})
    : assert(width > 0),
      assert(height > 0);

  final int width;
  final int height;

  final Logger _log = Logger('FfmpegH264Decoder');

  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();

  final StreamController<String> _errors = StreamController<String>.broadcast();

  Stream<Uint8List> get frames => _frames.stream;

  Stream<String> get errors => _errors.stream;

  final Queue<Uint8List> _pendingPackets = Queue<Uint8List>();

  static const int _maxPendingBytes = 8 * 1024 * 1024;
  Uint8List? _latestFrame;
  Uint8List? get latestFrame => _latestFrame;
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

  // ------------------------------------------------------------
  // DIAGNOSTIC COUNTERS
  // ------------------------------------------------------------

  int _inputPacketCount = 0;
  int _inputByteCount = 0;

  int _outputChunkCount = 0;
  int _outputByteCount = 0;

  int _outputFrameCount = 0;

  int get inputPacketCount => _inputPacketCount;
  int get inputByteCount => _inputByteCount;
  int get outputFrameCount => _outputFrameCount;

  // ------------------------------------------------------------
  // START
  // ------------------------------------------------------------

  Future<void> start(VideoService service) {
    if (_disposed) {
      throw StateError('The decoder has been disposed.');
    }

    return _startFuture ??= _startInternal(service);
  }

  Future<void> _startInternal(VideoService service) async {
    _frameBuffer = Uint8List(_frameSize);
    _ffmpegFinished = Completer<void>();

    _log.info(
      'Starting decoder: '
      'resolution=${width}x$height, '
      'frameSize=$_frameSize bytes, '
      'service=${identityHashCode(service)}.',
    );

    // Subscribe before launching FFmpeg so packets aren't lost
    // during decoder startup.
    _packetSubscription = service.videoPackets.listen(
      _handlePacket,
      onError: (Object error, StackTrace stackTrace) {
        _reportError('Video packet stream failed.', error, stackTrace);
      },
      onDone: () {
        _log.warning(
          'Video packet stream closed. '
          'Received=$_inputPacketCount packets, '
          'inputBytes=$_inputByteCount.',
        );
      },
    );
    final configPacket = service.codecConfigPacket;

    if (configPacket != null) {
      _log.info(
        'Replaying cached video codec configuration: '
        '${configPacket.payload.length} bytes.',
      );

      _handlePacket(configPacket);
    } else {
      _log.warning('No cached video codec configuration is available yet.');
    }
    try {
      final outputServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );

      _outputServer = outputServer;

      // Listen for FFmpeg's decoded raw RGBA output.
      _outputServerSubscription = outputServer.listen(_acceptOutputSocket);

      final inputPort = await _reservePort();

      final inputUrl = 'tcp://127.0.0.1:$inputPort?listen=1';
      final outputUrl = 'tcp://127.0.0.1:${outputServer.port}';

      final arguments = <String>[
        '-hide_banner',
        '-loglevel',
        'warning',
        '-f',
        'h264',
        '-i',
        inputUrl,
        '-an',
        '-sn',
        '-dn',
        '-vf',
        'scale=$width:$height',
        '-pix_fmt',
        'rgba',
        '-c:v',
        'rawvideo',
        '-f',
        'rawvideo',
        '-flush_packets',
        '1',
        outputUrl,
      ];

      _log.info(
        'Launching FFmpeg: '
        'inputPort=$inputPort, '
        'outputPort=${outputServer.port}.',
      );

      final session = await FFmpegKit.executeWithArgumentsAsync(arguments, (
        completedSession,
      ) async {
        try {
          final code = await completedSession.getReturnCode();
          final logs = await completedSession.getLogsAsString();

          _log.warning(
            'FFMPEG SESSION FINISHED: '
            'session=${completedSession.getSessionId()}, '
            'returnCode=$code, '
            'disposed=$_disposed, '
            'inputPackets=$_inputPacketCount, '
            'inputBytes=$_inputByteCount, '
            'outputFrames=$_outputFrameCount.',
          );

          if (logs.isNotEmpty) {
            _log.warning('FFMPEG FINAL LOGS:\n$logs');
          }

          if (!_disposed && !ReturnCode.isSuccess(code)) {
            _reportError('FFmpeg exited unsuccessfully: $code');
          }
        } catch (error, stackTrace) {
          _log.severe(
            'Could not read FFmpeg session result.',
            error,
            stackTrace,
          );
        } finally {
          final finished = _ffmpegFinished;

          if (finished != null && !finished.isCompleted) {
            finished.complete();
          }
        }
      });

      _sessionId = session.getSessionId();

      _log.info('FFmpeg session created: session=$_sessionId.');

      if (_disposed) {
        await FFmpegKit.cancel(_sessionId);
        return;
      }

      // Connect to FFmpeg's raw H.264 TCP input.
      _inputSocket = await _connectWithRetry(inputPort);

      _log.info(
        'FFmpeg input connected: '
        'pendingPackets=${_pendingPackets.length}, '
        'pendingBytes=$_pendingBytes.',
      );

      while (_pendingPackets.isNotEmpty) {
        final packet = _pendingPackets.removeFirst();
        _pendingBytes -= packet.length;
        _inputSocket!.add(packet);
      }

      await _inputSocket!.flush();

      _log.info(
        'Decoder ready: '
        'session=$_sessionId, '
        'resolution=${width}x$height.',
      );
    } catch (error, stackTrace) {
      final sessionId = _sessionId;

      if (sessionId != null) {
        try {
          await FFmpegKit.cancel(sessionId);
        } catch (cancelError, cancelStackTrace) {
          _log.warning(
            'Could not cancel failed FFmpeg session.',
            cancelError,
            cancelStackTrace,
          );
        }
      }

      _reportError('Failed to start FFmpeg decoder.', error, stackTrace);

      rethrow;
    }
  }

  // ------------------------------------------------------------
  // SOCKET SETUP
  // ------------------------------------------------------------

  Future<int> _reservePort() async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

    final port = probe.port;
    await probe.close();

    return port;
  }

  Future<Socket> _connectWithRetry(int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));

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

        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    throw StateError(
      'Could not connect to FFmpeg input on port $port: $lastError',
    );
  }

  void _acceptOutputSocket(Socket socket) {
    if (_disposed || _outputSocket != null) {
      _log.warning('Rejecting unexpected FFmpeg output socket.');

      socket.destroy();
      return;
    }

    _outputSocket = socket;

    _log.info(
      'Connected to FFmpeg decoded-video output: '
      '${socket.remoteAddress.address}:${socket.remotePort}.',
    );

    _outputSubscription = socket.listen(
      _handleDecodedBytes,
      onError: (Object error, StackTrace stackTrace) {
        if (!_disposed) {
          _reportError('FFmpeg output socket failed.', error, stackTrace);
        }
      },
      onDone: () {
        if (!_disposed) {
          _log.warning(
            'FFmpeg output stream closed. '
            'chunks=$_outputChunkCount, '
            'outputBytes=$_outputByteCount, '
            'frames=$_outputFrameCount, '
            'incompleteFrameBytes=$_frameOffset.',
          );
        }
      },
      cancelOnError: true,
    );
  }

  // ------------------------------------------------------------
  // H.264 INPUT
  // ------------------------------------------------------------

  void _handlePacket(VideoMediaPacket packet) {
    if (_disposed) return;

    var data = packet.payload;

    final originalLength = data.length;

    // Message 0x0000 carries an eight-byte timestamp before H.264 data.
    if (packet.messageId == 0x0000) {
      if (data.length <= 8) {
        _log.warning(
          'Dropping timestamped packet that is too short: '
          'bytes=${data.length}.',
        );
        return;
      }

      data = Uint8List.sublistView(data, 8);
    }

    if (data.isEmpty) return;

    _inputPacketCount++;
    _inputByteCount += data.length;

    // Log the first five packets, then every 120 packets.
    if (_inputPacketCount <= 5 || _inputPacketCount % 120 == 0) {
      _log.info(
        'FFMPEG INPUT #$_inputPacketCount: '
        'messageId=0x${packet.messageId.toRadixString(16).padLeft(4, '0')}, '
        'originalBytes=$originalLength, '
        'h264Bytes=${data.length}, '
        'totalH264Bytes=$_inputByteCount, '
        'socketConnected=${_inputSocket != null}.',
      );
    }

    final inputSocket = _inputSocket;

    if (inputSocket != null) {
      try {
        inputSocket.add(data);
      } catch (error, stackTrace) {
        _reportError(
          'Could not write H.264 data to FFmpeg.',
          error,
          stackTrace,
        );
      }

      return;
    }

    // Buffer packets during startup. Bound memory usage.
    final copy = Uint8List.fromList(data);

    while (_pendingPackets.isNotEmpty &&
        _pendingBytes + copy.length > _maxPendingBytes) {
      final dropped = _pendingPackets.removeFirst();
      _pendingBytes -= dropped.length;

      _log.warning('Dropping oldest startup packet: ${dropped.length} bytes.');
    }

    if (copy.length > _maxPendingBytes) {
      _log.warning(
        'Dropping oversized startup packet: '
        '${copy.length} bytes.',
      );
      return;
    }

    _pendingPackets.add(copy);
    _pendingBytes += copy.length;

    if (_inputPacketCount <= 5) {
      _log.info(
        'Buffered startup packet: '
        'pendingPackets=${_pendingPackets.length}, '
        'pendingBytes=$_pendingBytes.',
      );
    }
  }

  // ------------------------------------------------------------
  // DECODED RGBA OUTPUT
  // ------------------------------------------------------------

  void _handleDecodedBytes(List<int> bytes) {
    if (_disposed || bytes.isEmpty) return;

    _outputChunkCount++;
    _outputByteCount += bytes.length;

    // TCP chunks don't necessarily align to video-frame boundaries.
    if (_outputChunkCount <= 5 || _outputChunkCount % 60 == 0) {
      _log.info(
        'FFMPEG OUTPUT CHUNK #$_outputChunkCount: '
        'chunkBytes=${bytes.length}, '
        'totalOutputBytes=$_outputByteCount, '
        'frames=$_outputFrameCount, '
        'frameOffset=$_frameOffset.',
      );
    }

    var sourceOffset = 0;

    while (sourceOffset < bytes.length) {
      final available = _frameSize - _frameOffset;

      final count = math.min(available, bytes.length - sourceOffset);

      _frameBuffer.setRange(
        _frameOffset,
        _frameOffset + count,
        bytes,
        sourceOffset,
      );

      _frameOffset += count;
      sourceOffset += count;

      if (_frameOffset == _frameSize) {
        _outputFrameCount++;

        if (_outputFrameCount <= 5 || _outputFrameCount % 30 == 0) {
          _log.info(
            'FFMPEG OUTPUT FRAME #$_outputFrameCount: '
            'resolution=${width}x$height, '
            'frameBytes=$_frameSize, '
            'inputPackets=$_inputPacketCount, '
            'inputBytes=$_inputByteCount, '
            'outputBytes=$_outputByteCount.',
          );
        }

        final frame = Uint8List.fromList(_frameBuffer);
        _latestFrame = frame;
        _frames.add(frame);
        _frameOffset = 0;
      }
    }
  }

  // ------------------------------------------------------------
  // ERROR HANDLING
  // ------------------------------------------------------------

  void _reportError(String message, [Object? error, StackTrace? stackTrace]) {
    _log.severe(message, error, stackTrace);

    if (!_disposed && !_errors.isClosed) {
      _errors.add(error == null ? message : '$message $error');
    }
  }

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------

  Future<void> dispose() async {
    if (_disposed) return;

    _log.info(
      'Disposing decoder: '
      'session=$_sessionId, '
      'inputPackets=$_inputPacketCount, '
      'inputBytes=$_inputByteCount, '
      'outputFrames=$_outputFrameCount, '
      'outputBytes=$_outputByteCount.',
    );

    _disposed = true;

    await _packetSubscription?.cancel();

    try {
      await _inputSocket?.flush();
      await _inputSocket?.close();
    } catch (error, stackTrace) {
      _log.fine('Input socket was already closed.', error, stackTrace);
    }

    // Closing input should let FFmpeg finish normally.
    final finished = _ffmpegFinished;

    if (finished != null && !finished.isCompleted) {
      try {
        await finished.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        final sessionId = _sessionId;

        if (sessionId != null) {
          _log.warning(
            'FFmpeg did not exit after input closed; '
            'cancelling session $sessionId.',
          );

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
    } catch (error, stackTrace) {
      _log.fine('Output server was already closed.', error, stackTrace);
    }

    _pendingPackets.clear();
    _pendingBytes = 0;

    _latestFrame = null;

    await _frames.close();
    await _errors.close();

    _log.info('Decoder disposed.');
  }
}
