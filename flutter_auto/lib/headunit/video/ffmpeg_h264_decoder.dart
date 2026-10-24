import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter_auto/generated/oaa/video/VideoFPSEnum.pbenum.dart';
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

  // ------------------------------------------------------------
  // LIFECYCLE
  // ------------------------------------------------------------

  bool _disposed = false;
  Future<void>? _startFuture;
  Completer<void>? _ffmpegFinished;
  Completer<void> _disposeSignal = Completer<void>();

  int? _sessionId;

  // ------------------------------------------------------------
  // INPUT: DART SERVER -> FFMPEG CLIENT
  // ------------------------------------------------------------

  ServerSocket? _inputServer;
  StreamSubscription<Socket>? _inputServerSubscription;

  Socket? _inputSocket;
  StreamSubscription<List<int>>? _inputSocketSubscription;
  VideoService? _videoService;
  Completer<Socket>? _inputConnected;

  // ------------------------------------------------------------
  // OUTPUT: FFMPEG CLIENT -> DART SERVER
  // ------------------------------------------------------------

  ServerSocket? _outputServer;
  StreamSubscription<Socket>? _outputServerSubscription;

  Socket? _outputSocket;
  StreamSubscription<List<int>>? _outputSubscription;

  // ------------------------------------------------------------
  // VIDEO PACKET BUFFER
  // ------------------------------------------------------------

  final Queue<Uint8List> _pendingPackets = Queue<Uint8List>();

  static const int _maxPendingBytes = 8 * 1024 * 1024;

  int _pendingBytes = 0;

  Uint8List? _latestFrame;

  Uint8List? get latestFrame => _latestFrame;

  StreamSubscription<VideoMediaPacket>? _packetSubscription;

  // ------------------------------------------------------------
  // RAW RGBA FRAME ASSEMBLY
  // ------------------------------------------------------------

  late Uint8List _frameBuffer;

  int _frameOffset = 0;

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
    _videoService = service;
    return _startFuture ??= _startInternal(service);
  }

  Future<void> _startInternal(VideoService service) async {
    _frameBuffer = Uint8List(_frameSize);
    _ffmpegFinished = Completer<void>();
    _inputConnected = Completer<Socket>();

    _log.info(
      'Starting decoder: '
      'resolution=${width}x$height, '
      'frameSize=$_frameSize bytes, '
      'service=${identityHashCode(service)}.',
    );

    // Subscribe before launching FFmpeg so we do not miss early packets.
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

    // Replay a cached codec/configuration packet if available.
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
      if (_disposed) {
        throw StateError('Decoder was disposed during startup.');
      }

      // ----------------------------------------------------------
      // 1. Start the output server.
      //
      // FFmpeg connects here to send decoded RGBA video frames.
      // ----------------------------------------------------------

      final outputServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );

      _outputServer = outputServer;

      _outputServerSubscription = outputServer.listen(_acceptOutputSocket);

      if (_disposed) {
        throw StateError('Decoder was disposed during startup.');
      }

      // ----------------------------------------------------------
      // 2. Start the input server.
      //
      // Dart listens here.
      // FFmpeg connects to this server as a TCP client.
      //
      // This avoids FFmpeg's TCP listen=1 startup dependency.
      // ----------------------------------------------------------

      final inputServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );

      _inputServer = inputServer;

      _inputServerSubscription = inputServer.listen(_acceptInputSocket);

      final inputUrl = 'tcp://127.0.0.1:${inputServer.port}';

      final outputUrl = 'tcp://127.0.0.1:${outputServer.port}';

      // ----------------------------------------------------------
      // 3. FFmpeg arguments.
      //
      // Input is a raw H.264 stream.
      // Output is raw RGBA video sent over TCP.
      // ----------------------------------------------------------
      final fps = _videoService!.fps == VideoFPS_Enum.x30_ ? '30' : '60'; 
      final arguments = <String>[
        '-hide_banner',
        '-loglevel',
        'warning',

        '-threads',
        '1',

        '-f',
        'h264',
        '-i',
        inputUrl,

        '-an',
        '-sn',
        '-dn',

        '-vf',
        'scale=$width:$height,setpts=N/($fps*TB)',

        '-pix_fmt',
        'rgba',

        '-c:v',
        'rawvideo',

        '-r',
        '30',
        '-fps_mode',
        'cfr',

        '-f',
        'rawvideo',
        '-flush_packets',
        '1',

        outputUrl,
      ];

      _log.info(
        'Launching FFmpeg: '
        'inputPort=${inputServer.port}, '
        'outputPort=${outputServer.port}.',
      );

      final session = await FFmpegKit.executeWithArgumentsAsync(
        arguments,
        (completedSession) async {
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
        },
        (log) {
          final message = log.getMessage().trim();

          if (message.isNotEmpty) {
            _log.fine('FFmpeg: $message');
          }
        },
      );

      _sessionId = session.getSessionId();

      _log.info('FFmpeg session created: session=$_sessionId.');

      if (_disposed) {
        final sessionId = _sessionId;

        if (sessionId != null) {
          await FFmpegKit.cancel(sessionId);
        }

        return;
      }

      // ----------------------------------------------------------
      // 4. Wait for FFmpeg to connect to the Dart input server.
      //
      // Race the connection against FFmpeg exiting early so we
      // report a useful error instead of retrying a dead session.
      // ----------------------------------------------------------

      final inputServerPort = inputServer.port;

      final connectedSocketFuture = _inputConnected!.future;

      final ffmpegExitedFuture = _ffmpegFinished!.future.then<Socket>((_) {
        throw StateError(
          'FFmpeg exited before connecting to the H.264 input server '
          'on port $inputServerPort.',
        );
      });

      final disposeFuture = _disposeSignal.future.then<Socket>((_) {
        throw StateError(
          'Decoder was disposed while waiting for FFmpeg to connect.',
        );
      });

      final inputSocket =
          await Future.any<Socket>([
            connectedSocketFuture,
            ffmpegExitedFuture,
            disposeFuture,
          ]).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw StateError(
                'FFmpeg did not connect to the H.264 input server '
                'on port $inputServerPort within 10 seconds.',
              );
            },
          );

      if (_disposed) {
        return;
      }

      _log.info(
        'FFmpeg input connected: '
        'port=$inputServerPort, '
        'pendingPackets=${_pendingPackets.length}, '
        'pendingBytes=$_pendingBytes.',
      );

      // The input socket handler flushes pending packets before
      // completing _inputConnected, preserving packet order.
      _log.info(
        'Decoder ready: '
        'session=$_sessionId, '
        'resolution=${width}x$height, '
        'inputSocket=${inputSocket.remoteAddress.address}:'
        '${inputSocket.remotePort}.',
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

      if (!_disposed) {
        _reportError('Failed to start FFmpeg decoder.', error, stackTrace);
      }

      rethrow;
    }
  }

  // ------------------------------------------------------------
  // INPUT SOCKET HANDLER
  // ------------------------------------------------------------

  void _acceptInputSocket(Socket socket) {
    if (_disposed || _inputSocket != null) {
      _log.warning('Rejecting unexpected FFmpeg input connection.');
      socket.destroy();
      return;
    }

    _inputSocket = socket;

    _log.info(
      'FFmpeg connected to H.264 input server: '
      '${socket.remoteAddress.address}:${socket.remotePort}.',
    );

    // Observe socket closure and errors while we write video data.
    _inputSocketSubscription = socket.listen(
      (_) {
        // FFmpeg is not expected to send video data back on this socket.
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_disposed) {
          _reportError('FFmpeg input socket failed.', error, stackTrace);
        }
      },
      onDone: () {
        if (identical(_inputSocket, socket)) {
          _inputSocket = null;
        }

        if (!_disposed) {
          _log.warning(
            'FFmpeg input socket closed. '
            'inputPackets=$_inputPacketCount, '
            'inputBytes=$_inputByteCount.',
          );
        }
      },
      cancelOnError: true,
    );

    // IMPORTANT: send buffered packets before signalling that the
    // connection is ready. Otherwise newly arriving packets could
    // overtake packets buffered during startup.
    try {
      while (_pendingPackets.isNotEmpty) {
        final packet = _pendingPackets.removeFirst();
        _pendingBytes -= packet.length;
        socket.add(packet);
      }
    } catch (error, stackTrace) {
      _inputSocket = null;
      socket.destroy();

      final connected = _inputConnected;

      if (connected != null && !connected.isCompleted) {
        connected.completeError(error, stackTrace);
      }

      _reportError(
        'Could not flush buffered H.264 packets to FFmpeg.',
        error,
        stackTrace,
      );

      return;
    }

    final connected = _inputConnected;

    if (connected != null && !connected.isCompleted) {
      connected.complete(socket);
    }
  }

  // ------------------------------------------------------------
  // OUTPUT SOCKET HANDLER
  // ------------------------------------------------------------

  void _acceptOutputSocket(Socket socket) {
    if (_disposed || _outputSocket != null) {
      _log.warning('Rejecting unexpected FFmpeg output connection.');
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
  // H.264 INPUT PACKETS
  // ------------------------------------------------------------

  void _handlePacket(VideoMediaPacket packet) {
    if (_disposed) return;

    var data = packet.payload;

    final originalLength = data.length;

    // Message 0x0000 is assumed to carry an eight-byte timestamp
    // before H.264 data. Confirm this against your protocol framing.
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
      _log.fine(
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

    // FFmpeg has not connected yet. Buffer the packets, bounded
    // to avoid unbounded memory consumption during startup.
    if (data.length > _maxPendingBytes) {
      _log.warning('Dropping oversized startup packet: ${data.length} bytes.');
      return;
    }

    while (_pendingPackets.isNotEmpty &&
        _pendingBytes + data.length > _maxPendingBytes) {
      final dropped = _pendingPackets.removeFirst();
      _pendingBytes -= dropped.length;

      _log.warning('Dropping oldest startup packet: ${dropped.length} bytes.');
    }

    final copy = Uint8List.fromList(data);

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

    // TCP chunks do not necessarily align with video frame boundaries.
    if (_outputChunkCount <= 5 || _outputChunkCount % 60 == 0) {
      _log.fine(
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
          _log.fine(
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

    // Unblock startup if it is still waiting for a connection.
    if (!_disposeSignal.isCompleted) {
      _disposeSignal.complete();
    }

    await _packetSubscription?.cancel();
    _packetSubscription = null;

    // Close the input connection first, signalling EOF to FFmpeg.
    try {
      await _inputSocket?.flush();
      await _inputSocket?.close();
    } catch (error, stackTrace) {
      _log.fine('Input socket was already closed.', error, stackTrace);
    }

    _inputSocket = null;

    await _inputSocketSubscription?.cancel();
    _inputSocketSubscription = null;

    // Stop accepting any further FFmpeg input connections.
    await _inputServerSubscription?.cancel();
    _inputServerSubscription = null;

    try {
      await _inputServer?.close();
    } catch (error, stackTrace) {
      _log.fine('Input server was already closed.', error, stackTrace);
    }

    _inputServer = null;

    // Give FFmpeg a chance to finish after receiving input EOF.
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

          try {
            await FFmpegKit.cancel(sessionId);
          } catch (error, stackTrace) {
            _log.warning('Failed to cancel FFmpeg session.', error, stackTrace);
          }
        }
      }
    }

    await _outputSubscription?.cancel();
    _outputSubscription = null;

    await _outputServerSubscription?.cancel();
    _outputServerSubscription = null;

    _outputSocket?.destroy();
    _outputSocket = null;

    try {
      await _outputServer?.close();
    } catch (error, stackTrace) {
      _log.fine('Output server was already closed.', error, stackTrace);
    }

    _outputServer = null;

    // Release buffered packets and the latest displayed frame.
    _pendingPackets.clear();
    _pendingBytes = 0;

    _latestFrame = null;
    _frameOffset = 0;

    if (!_frames.isClosed) {
      await _frames.close();
    }

    if (!_errors.isClosed) {
      await _errors.close();
    }

    _log.info('Decoder disposed.');
  }
}
