import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:headunit_runtime/headunit_runtime.dart';

import 'h264_annex_b_parser.dart';

/// Runs a local producer against the same authenticated media protocol used by
/// an external Flutter application. It exists only in the runtime example.
///
/// The H.264 asset is a short, synthetic test pattern. It is split into
/// Annex-B access units and sent through [MediaStreamClient], received by
/// [LocalMediaServer], and displayed by [RemoteVideoSurface]/FFmpegKit.
class RemoteVideoDemoController {
  RemoteVideoDemoController._({
    required this.server,
    required this.client,
    required this.connection,
    required this._accessUnits,
    required this.configuration,
  });

  static const String _assetPath = 'assets/remote_video_demo.h264';
  static const VideoStreamConfiguration _configuration =
      VideoStreamConfiguration(
        codec: VideoCodec.h264,
        width: 640,
        height: 360,
        framesPerSecond: 20,
        targetBitrateBitsPerSecond: 600000,
      );
  static const Duration _connectionTimeout = Duration(seconds: 5);

  final LocalMediaServer server;
  final MediaStreamClient client;
  final MediaStreamConnection connection;
  final List<H264AccessUnit> _accessUnits;
  final VideoStreamConfiguration configuration;
  final ValueNotifier<int> framesSent = ValueNotifier<int>(0);
  final ValueNotifier<Object?> error = ValueNotifier<Object?>(null);

  bool _running = false;
  bool _disposed = false;
  Future<void>? _sendTask;
  Future<void>? _disposeFuture;

  static Future<RemoteVideoDemoController> create() async {
    final ByteData asset = await rootBundle.load(_assetPath);
    final Uint8List bytes = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );
    final List<H264AccessUnit> accessUnits = H264AnnexBParser.parse(bytes);

    final Random random = Random.secure();
    final String token = List<int>.generate(
      32,
      (int index) => random.nextInt(256),
      growable: false,
    ).map((int value) => value.toRadixString(16).padLeft(2, '0')).join();

    final LocalMediaServer server = await LocalMediaServer.bind(
      token: token,
      configuration: _configuration,
      maxConnections: 1,
      maxQueuedFrames: 2,
    );

    MediaStreamClient? client;
    try {
      final Future<MediaStreamConnection> acceptedConnection = server
          .connections
          .first
          .timeout(_connectionTimeout);

      final MediaStreamClient connectedClient =
          await MediaStreamClient.connect(
        host: server.host,
        port: server.port,
        token: token,
        timeout: _connectionTimeout,
      );
      client = connectedClient;
      final MediaStreamConnection connection = await acceptedConnection;

      return RemoteVideoDemoController._(
        server: server,
        client: connectedClient,
        connection: connection,
        _accessUnits: accessUnits,
        configuration: _configuration,
      );
    } catch (_) {
      await client?.close();
      await server.close();
      rethrow;
    }
  }

  void start() {
    if (_disposed) {
      throw StateError('The remote video demo has been disposed.');
    }
    if (_running) {
      return;
    }

    _running = true;
    _sendTask = _sendLoop();
  }

  Future<void> _sendLoop() async {
    final Stopwatch clock = Stopwatch()..start();
    final int frameIntervalMicros =
        Duration(seconds: 1).inMicroseconds ~/ configuration.framesPerSecond;
    int accessUnitIndex = 0;
    int sequenceNumber = 0;
    int nextFrameDeadlineMicros = 0;

    try {
      while (_running && !client.isClosed) {
        final H264AccessUnit accessUnit = _accessUnits[accessUnitIndex];
        accessUnitIndex = (accessUnitIndex + 1) % _accessUnits.length;

        // Respect the receiver's backpressure/keyframe requests. The demo
        // stream repeats an IDR every two seconds, so recovery is deterministic.
        if (client.requiresKeyFrame && !accessUnit.isKeyFrame) {
          nextFrameDeadlineMicros += frameIntervalMicros;
          await _waitUntil(clock, nextFrameDeadlineMicros);
          continue;
        }

        await client.sendFrame(
          EncodedVideoFrame(
            sequenceNumber: sequenceNumber,
            presentationTimeMicros: clock.elapsedMicroseconds,
            isKeyFrame: accessUnit.isKeyFrame,
            data: accessUnit.data,
          ),
        );
        sequenceNumber++;
        framesSent.value = sequenceNumber;

        nextFrameDeadlineMicros += frameIntervalMicros;
        await _waitUntil(clock, nextFrameDeadlineMicros);
      }
    } catch (exception) {
      if (_running) {
        error.value = exception;
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _waitUntil(Stopwatch clock, int deadlineMicros) async {
    final int remainingMicros = deadlineMicros - clock.elapsedMicroseconds;
    if (remainingMicros > 0) {
      await Future<void>.delayed(Duration(microseconds: remainingMicros));
    }
  }

  Future<void> dispose() => _disposeFuture ??= _disposeCore();

  Future<void> _disposeCore() async {
    _disposed = true;
    _running = false;

    final Future<void>? sendTask = _sendTask;
    if (sendTask != null) {
      await sendTask;
    }

    await client.close();
    await server.close();
    framesSent.dispose();
    error.dispose();
  }
}
