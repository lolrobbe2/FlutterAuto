import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../flutter_auto_core/lib/headunit/drivers/input/touch_driver.dart';
import '../../../flutter_auto_core/lib/headunit/headunit_session.dart';
import '../../../flutter_auto_core/lib/headunit/input/touch_input.dart';
import '../../../flutter_auto_core/lib/headunit/service/video_service.dart';
import '../../../flutter_auto_core/lib/headunit/video/ffmpeg_h264_decoder.dart';
import '../../../flutter_auto_core/lib/headunit/video/head_unit_view.dart';
import '../../../flutter_auto_core/lib/headunit/video/video_message_id.dart';
import 'package:logging/logging.dart';

class HeadunitServerScreen extends StatefulWidget {
  const HeadunitServerScreen({
    super.key,
    required this.deviceSerial,
    required this.session,
    this.videoBuilder,
  });

  final String deviceSerial;
  final HeadunitSession session;

  /// Builds a rendering view using the screen-owned decoder.
  ///
  /// The returned widget must not start or dispose the decoder.
  final Widget Function(BuildContext context, FfmpegH264Decoder decoder)?
  videoBuilder;

  @override
  State<HeadunitServerScreen> createState() => _HeadunitServerScreenState();
}

class _HeadunitServerScreenState extends State<HeadunitServerScreen> {
  final Logger _log = Logger('HeadunitServerScreen');

  StreamSubscription<HeadunitSessionState>? _sessionSubscription;
  StreamSubscription<VideoMediaPacket>? _videoSubscription;

  late HeadunitSessionState _sessionState;
  late FfmpegH264Decoder _decoder;

  bool _isFullscreen = false;

  int _packetCount = 0;
  int _totalBytes = 0;
  int? _lastMessageId;
  DateTime? _lastPacketAt;

  String? _videoError;
  String? _decoderError;

  VideoService get _video => widget.session.videoService;
  late TouchInput _touchInput;
  @override
  void initState() {
    super.initState();

    _sessionState = widget.session.state;
    _touchInput = TouchInput(
      width: _video.resolution.dimensions.width,
      height: _video.resolution.dimensions.height,
    );
    widget.session.inputService.addInput(_touchInput);
    // The screen owns the decoder, not the rendering widget.
    _decoder = _createDecoder();

    unawaited(_startDecoder(_decoder, _video));

    _subscribeToSession(widget.session);
    _subscribeToVideo(_video);
  }

  FfmpegH264Decoder _createDecoder() {
    return FfmpegH264Decoder(width: 800, height: 480);
  }

  Future<void> _startDecoder(
    FfmpegH264Decoder decoder,
    VideoService service,
  ) async {
    _log.info(
      'Starting screen-owned decoder: '
      'decoder=${identityHashCode(decoder)}, '
      'service=${identityHashCode(service)}.',
    );

    try {
      await decoder.start(service);

      _log.info(
        'Screen-owned decoder started: '
        'decoder=${identityHashCode(decoder)}.',
      );

      if (!mounted || !identical(_decoder, decoder)) {
        return;
      }

      setState(() {
        _decoderError = null;
      });
    } catch (error, stackTrace) {
      _log.severe('Failed to start video decoder.', error, stackTrace);

      if (!mounted || !identical(_decoder, decoder)) {
        return;
      }

      setState(() {
        _decoderError = error.toString();
      });
    }
  }

  void _subscribeToSession(HeadunitSession session) {
    _sessionSubscription = session.states.listen((state) {
      if (!mounted) return;

      setState(() {
        _sessionState = state;
      });
    });
  }

  void _subscribeToVideo(VideoService service) {
    _videoSubscription = service.videoPackets.listen(
      (packet) {
        if (!mounted) return;

        setState(() {
          _packetCount++;
          _totalBytes += packet.payload.length;
          _lastMessageId = packet.messageId;
          _lastPacketAt = DateTime.now();
          _videoError = null;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        _log.severe('Video packet stream error.', error, stackTrace);

        if (!mounted) return;

        setState(() {
          _videoError = error.toString();
        });
      },
    );
  }

  Widget _buildVideoSurface(ThemeData theme) {
    return TouchInputDriver(
      touchInput: _touchInput,
      child: HeadunitVideoView(
        resolution: _video.resolution,
        decoder: _decoder,
        videoBuilder: widget.videoBuilder,
        borderRadius: _isFullscreen ? 0 : 12,
        backgroundColor: Colors.black,
        showPlaceholder: true,
      ),
    );
  }

  Future<void> _toggleFullscreen() async {
    if (!mounted) return;

    final enterFullscreen = !_isFullscreen;

    setState(() {
      _isFullscreen = enterFullscreen;
    });

    _log.info(
      'Fullscreen ${enterFullscreen ? "enabled" : "disabled"}: '
      'decoder=${identityHashCode(_decoder)}, '
      'inputPackets=${_decoder.inputPacketCount}, '
      'outputFrames=${_decoder.outputFrameCount}.',
    );

    try {
      await SystemChrome.setEnabledSystemUIMode(
        enterFullscreen
            ? SystemUiMode.immersiveSticky
            : SystemUiMode.edgeToEdge,
      );
    } catch (error, stackTrace) {
      _log.warning('Failed to change system UI mode.', error, stackTrace);

      if (mounted) {
        setState(() {
          _isFullscreen = !enterFullscreen;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant HeadunitServerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.session == widget.session) {
      return;
    }

    _log.info(
      'Head-unit session changed. Replacing decoder and subscriptions.',
    );

    _sessionSubscription?.cancel();
    _videoSubscription?.cancel();

    // Replace the decoder only when the underlying session changes.
    final previousDecoder = _decoder;
    final nextDecoder = _createDecoder();

    _decoder = nextDecoder;

    _sessionState = widget.session.state;

    _packetCount = 0;
    _totalBytes = 0;
    _lastMessageId = null;
    _lastPacketAt = null;

    _videoError = null;
    _decoderError = null;

    unawaited(previousDecoder.dispose());

    _subscribeToSession(widget.session);
    _subscribeToVideo(widget.session.videoService);

    unawaited(_startDecoder(nextDecoder, widget.session.videoService));
  }

  @override
  void dispose() {
    _log.info(
      'Disposing HeadunitServerScreen: '
      'decoder=${identityHashCode(_decoder)}, '
      'inputPackets=${_decoder.inputPacketCount}, '
      'outputFrames=${_decoder.outputFrameCount}.',
    );

    _sessionSubscription?.cancel();
    _videoSubscription?.cancel();

    // The decoder is disposed when its owner goes away,
    // not when the video view changes between layouts.
    unawaited(_decoder.dispose());

    if (_isFullscreen) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
        ).catchError((Object error, StackTrace stackTrace) {
          _log.warning('Could not restore system UI mode.', error, stackTrace);
        }),
      );
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // ------------------------------------------------------------
    // FULLSCREEN MODE
    // ------------------------------------------------------------
    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Let the video surface calculate its own aspect-ratio-preserving
            // size. The Scaffold background fills the unused area with black.
            Center(child: _buildVideoSurface(theme)),

            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    tooltip: 'Exit fullscreen',
                    onPressed: _toggleFullscreen,
                    icon: const Icon(
                      Icons.fullscreen_exit,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ------------------------------------------------------------
    // NORMAL DASHBOARD
    // ------------------------------------------------------------
    return Scaffold(
      appBar: AppBar(
        title: const Text('Android Auto Head Unit'),
        actions: [
          IconButton(
            tooltip: 'Fullscreen video',
            icon: const Icon(Icons.fullscreen),
            onPressed: _toggleFullscreen,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _StatusChip(
                label: _sessionState.name,
                color: _sessionColor(colors),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Projection display',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Text(
                  '${_video.resolution.dimensions.width} × '
                  '${_video.resolution.dimensions.height}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildVideoSurface(theme),
            const SizedBox(height: 20),

            Text('Video pipeline', style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),

            _VideoStatusCard(
              isSetup: _video.isSetup,
              isStreaming: _video.isStreaming,
              focusMode: _video.focusMode?.name ?? 'Not negotiated',
              sessionId: _video.sessionId,
              packetCount: _packetCount,
              totalBytes: _totalBytes,
              lastMessageId: _lastMessageId,
              lastPacketAt: _lastPacketAt,
              error: _decoderError ?? _videoError,
            ),

            const SizedBox(height: 16),

            Text(
              'FFmpeg input: ${_decoder.inputPacketCount} · '
              'output frames: ${_decoder.outputFrameCount}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlaceholder(ThemeData theme) {
    final colors = theme.colorScheme;

    final String subtitle;

    if (_decoderError != null) {
      subtitle = 'Decoder failed: $_decoderError';
    } else if (_packetCount > 0 && _decoder.outputFrameCount > 0) {
      subtitle = 'Video frames decoded; renderer not attached';
    } else if (_packetCount > 0) {
      subtitle = 'Receiving encoded video; waiting for decoded frames';
    } else if (_sessionState != HeadunitSessionState.connected) {
      subtitle = 'Waiting for an active Android Auto session';
    } else if (!_video.isSetup) {
      subtitle = 'Waiting for video AV setup';
    } else if (!_video.isStreaming) {
      subtitle = 'Video configured; waiting for stream start';
    } else {
      subtitle = 'Stream started; waiting for video packets';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.ondemand_video,
              size: 56,
              color: colors.onSurface.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 12),
            const Text(
              'Video output',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
            ),
            if (_packetCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                '$_packetCount packets · ${_formatBytes(_totalBytes)}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'FFmpeg input: ${_decoder.inputPacketCount} · '
              'output frames: ${_decoder.outputFrameCount}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Color _sessionColor(ColorScheme colors) {
    switch (_sessionState) {
      case HeadunitSessionState.connected:
        return colors.tertiary;
      case HeadunitSessionState.connecting:
      case HeadunitSessionState.negotiatingVersion:
        return colors.primary;
      case HeadunitSessionState.failed:
        return colors.error;
      case HeadunitSessionState.disconnecting:
      case HeadunitSessionState.disconnected:
        return colors.outline;
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

// ==================================================================
// CONNECTION CARD
// ==================================================================

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.deviceSerial,
    required this.state,
    required this.color,
  });

  final String deviceSerial;
  final HeadunitSessionState state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.smartphone, size: 32, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connected device', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(deviceSerial),
                  const SizedBox(height: 4),
                  Text(
                    state.name,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ],
              ),
            ),
            if (state == HeadunitSessionState.connecting ||
                state == HeadunitSessionState.negotiatingVersion)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================================================================
// VIDEO STATUS CARD
// ==================================================================

class _VideoStatusCard extends StatelessWidget {
  const _VideoStatusCard({
    required this.isSetup,
    required this.isStreaming,
    required this.focusMode,
    required this.sessionId,
    required this.packetCount,
    required this.totalBytes,
    required this.lastMessageId,
    required this.lastPacketAt,
    required this.error,
  });

  final bool isSetup;
  final bool isStreaming;
  final String focusMode;
  final int? sessionId;
  final int packetCount;
  final int totalBytes;
  final int? lastMessageId;
  final DateTime? lastPacketAt;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _MetricRow(
              label: 'AV setup',
              value: isSetup ? 'Accepted' : 'Waiting',
              good: isSetup,
            ),
            _MetricRow(
              label: 'Stream',
              value: isStreaming ? 'Started' : 'Stopped',
              good: isStreaming,
            ),
            _MetricRow(label: 'Video focus', value: focusMode),
            _MetricRow(
              label: 'Video session ID',
              value: sessionId?.toString() ?? '—',
            ),
            _MetricRow(label: 'Received packets', value: '$packetCount'),
            _MetricRow(label: 'Encoded data', value: _formatBytes(totalBytes)),
            _MetricRow(
              label: 'Last message ID',
              value: lastMessageId == null
                  ? '—'
                  : '0x${lastMessageId!.toRadixString(16).padLeft(4, '0')}',
            ),
            _MetricRow(
              label: 'Last packet',
              value: lastPacketAt == null
                  ? '—'
                  : TimeOfDay.fromDateTime(lastPacketAt!).format(context),
            ),
            if (error != null) ...[
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

// ==================================================================
// METRIC ROW
// ==================================================================

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value, this.good});

  final String label;
  final String value;
  final bool? good;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          if (good != null) ...[
            Icon(
              good! ? Icons.check_circle : Icons.schedule,
              size: 16,
              color: good! ? colors.tertiary : colors.outline,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================================================================
// STATUS CHIP
// ==================================================================

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
