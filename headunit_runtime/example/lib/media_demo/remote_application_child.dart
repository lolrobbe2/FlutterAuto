import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:headunit_sdk/headunit_sdk.dart';

import 'h264_annex_b_parser.dart';
import 'remote_demo_service.dart';

/// Entry point used when the same Windows bundle is launched as an external
/// application by the headunit. The parent sends its session endpoint through
/// the child's private stdin pipe as one JSON line.
class RemoteApplicationChildProcess {
  static const String _videoAsset = 'assets/remote_video_demo.h264';
  static const Duration _bootstrapTimeout = Duration(seconds: 5);

  static Future<void> run() async {
    final String bootstrapLine = await stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(_bootstrapTimeout);
    final _RemoteApplicationEndpoint endpoint =
        _RemoteApplicationEndpoint.fromJson(bootstrapLine);

    final HeadunitConnection connection = await HeadunitConnection.connect(
      host: endpoint.host,
      port: endpoint.port,
      mediaPort: endpoint.mediaPort,
      token: endpoint.token,
      timeout: const Duration(seconds: 10),
    );

    try {
      final MediaStreamClient media = await connection.openMediaStream();
      final ByteData asset = await rootBundle.load(_videoAsset);
      final Uint8List bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final List<H264AccessUnit> accessUnits = H264AnnexBParser.parse(bytes);

      // This real SDK acquisition exercises the authenticated service RPC
      // path independently of the H.264 media transport.
      final RemoteDemoService demoService = await connection.services.acquire(
        RemoteDemoService.key,
      );
      final String serviceStatus = await demoService.getStatus();

      final _RemoteH264Sender sender = _RemoteH264Sender(
        client: media,
        accessUnits: accessUnits,
      );

      bool shuttingDown = false;
      late final StreamSubscription<HeadunitHostEvent> lifecycleSubscription;

      Future<void> shutdown() async {
        if (shuttingDown) {
          return;
        }
        shuttingDown = true;
        await lifecycleSubscription.cancel();
        await sender.dispose();
        await connection.close();
        exit(0);
      }

      lifecycleSubscription = connection.notifications.listen(
        (HeadunitHostEvent event) {
          if (event.method == 'application.lifecycle' &&
              event.parameters['state'] == 'stopping') {
            unawaited(shutdown());
          }
        },
        onDone: () => unawaited(shutdown()),
      );

      runApp(
        _RemoteApplicationChildApp(
          connection: connection,
          serviceStatus: serviceStatus,
        ),
      );
      sender.start();
    } catch (_) {
      await connection.close();
      rethrow;
    }
  }
}

class _RemoteApplicationEndpoint {
  final String host;
  final int port;
  final int mediaPort;
  final String token;

  const _RemoteApplicationEndpoint({
    required this.host,
    required this.port,
    required this.mediaPort,
    required this.token,
  });

  factory _RemoteApplicationEndpoint.fromJson(String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map) {
      throw const FormatException('The headunit bootstrap must be an object.');
    }

    final Object? host = decoded['host'];
    final Object? port = decoded['port'];
    final Object? mediaPort = decoded['mediaPort'];
    final Object? token = decoded['token'];

    if (host is! String ||
        host != '127.0.0.1' ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        mediaPort is! int ||
        mediaPort < 1 ||
        mediaPort > 65535 ||
        token is! String ||
        token.isEmpty) {
      throw const FormatException('Invalid headunit bootstrap endpoint.');
    }

    return _RemoteApplicationEndpoint(
      host: host,
      port: port,
      mediaPort: mediaPort,
      token: token,
    );
  }
}

class _RemoteH264Sender {
  static const int _framesPerSecond = 20;

  final MediaStreamClient _client;
  final List<H264AccessUnit> _accessUnits;

  bool _running = false;
  Future<void>? _sendTask;

  _RemoteH264Sender({
    required MediaStreamClient client,
    required List<H264AccessUnit> accessUnits,
  }) : _client = client,
       _accessUnits = accessUnits;

  void start() {
    if (_running) {
      return;
    }
    _running = true;
    _sendTask = _sendLoop();
  }

  Future<void> _sendLoop() async {
    final Stopwatch clock = Stopwatch()..start();
    final int frameIntervalMicros =
        Duration(seconds: 1).inMicroseconds ~/ _framesPerSecond;
    int accessUnitIndex = 0;
    int sequenceNumber = 0;
    int nextFrameDeadlineMicros = 0;

    try {
      while (_running && !_client.isClosed) {
        final H264AccessUnit accessUnit = _accessUnits[accessUnitIndex];
        accessUnitIndex = (accessUnitIndex + 1) % _accessUnits.length;

        if (_client.requiresKeyFrame && !accessUnit.isKeyFrame) {
          nextFrameDeadlineMicros += frameIntervalMicros;
          await _waitUntil(clock, nextFrameDeadlineMicros);
          continue;
        }

        await _client.sendFrame(
          EncodedVideoFrame(
            sequenceNumber: sequenceNumber,
            presentationTimeMicros: clock.elapsedMicroseconds,
            isKeyFrame: accessUnit.isKeyFrame,
            data: accessUnit.data,
          ),
        );
        sequenceNumber++;

        nextFrameDeadlineMicros += frameIntervalMicros;
        await _waitUntil(clock, nextFrameDeadlineMicros);
      }
    } catch (error) {
      if (_running) {
        stderr.writeln('External application video sender failed: $error');
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

  Future<void> dispose() async {
    _running = false;
    await _sendTask;
    // HeadunitConnection owns and closes this media client.
  }
}

class _RemoteApplicationChildApp extends StatelessWidget {
  final HeadunitConnection connection;
  final String serviceStatus;

  const _RemoteApplicationChildApp({
    required this.connection,
    required this.serviceStatus,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'External Flutter Application',
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('External Flutter application')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Application: ${connection.applicationId.value}'),
              const SizedBox(height: 8),
              const Text('Process: separate Flutter engine / OS process'),
              const SizedBox(height: 8),
              Text('SDK service: $serviceStatus'),
              const SizedBox(height: 24),
              const Text('Last touch event received from the headunit:'),
              const SizedBox(height: 8),
              StreamBuilder<ApplicationPointerEvent>(
                stream: connection.pointerEvents,
                builder: (
                  BuildContext context,
                  AsyncSnapshot<ApplicationPointerEvent> snapshot,
                ) {
                  final ApplicationPointerEvent? event = snapshot.data;
                  if (event == null) {
                    return const Text('Waiting for touch input...');
                  }
                  return Text(
                    '${event.phase.name} · pointer ${event.pointerId} · '
                    'x=${event.x.toStringAsFixed(3)} · '
                    'y=${event.y.toStringAsFixed(3)}',
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
