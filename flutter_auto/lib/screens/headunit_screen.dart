import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_auto/headunit/headunit_session.dart';
import 'package:flutter_auto/headunit/service/video_service.dart';

class HeadunitServerScreen extends StatefulWidget {
  const HeadunitServerScreen({
    super.key,
    required this.deviceSerial,
    required this.session,
    this.videoBuilder,
  });

  final String deviceSerial;
  final HeadunitSession session;

  /// Supply a decoder/rendering widget here when the H.264 decoder is ready.
  /// It can subscribe to [VideoService.videoPackets].
  final Widget Function(BuildContext context, VideoService videoService)?
      videoBuilder;

  @override
  State<HeadunitServerScreen> createState() =>
      _HeadunitServerScreenState();
}

class _HeadunitServerScreenState extends State<HeadunitServerScreen> {
  StreamSubscription<HeadunitSessionState>? _sessionSubscription;
  StreamSubscription<VideoMediaPacket>? _videoSubscription;

  late HeadunitSessionState _sessionState;

  int _packetCount = 0;
  int _totalBytes = 0;
  int? _lastMessageId;
  DateTime? _lastPacketAt;
  String? _videoError;

  VideoService get _video => widget.session.videoService;

  @override
  void initState() {
    super.initState();

    _sessionState = widget.session.state;

    _sessionSubscription = widget.session.states.listen((state) {
      if (!mounted) return;
      setState(() => _sessionState = state);
    });

    _subscribeToVideo(widget.session.videoService);
  }

  @override
  void didUpdateWidget(covariant HeadunitServerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.session != widget.session) {
      _sessionSubscription?.cancel();
      _videoSubscription?.cancel();

      _sessionState = widget.session.state;
      _packetCount = 0;
      _totalBytes = 0;
      _lastMessageId = null;
      _lastPacketAt = null;

      _sessionSubscription = widget.session.states.listen((state) {
        if (!mounted) return;
        setState(() => _sessionState = state);
      });

      _subscribeToVideo(widget.session.videoService);
    }
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
        if (!mounted) return;
        setState(() => _videoError = error.toString());
      },
    );
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _videoSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Android Auto Head Unit'),
        actions: [
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ConnectionCard(
                  deviceSerial: widget.deviceSerial,
                  state: _sessionState,
                  color: _sessionColor(colors),
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Projection display',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    Text(
                      '800 × 480',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Dedicated video output. The decoder widget will replace
                // the placeholder without changing the surrounding screen.
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: Colors.black,
                    child: AspectRatio(
                      aspectRatio: 800 / 480,
                      child: widget.videoBuilder != null
                          ? widget.videoBuilder!(context, _video)
                          : _buildVideoPlaceholder(theme),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                Text(
                  'Video pipeline',
                  style: theme.textTheme.titleLarge,
                ),
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
                  error: _videoError,
                ),

                const SizedBox(height: 16),
                Text(
                  'The protocol session and video rendering are separate '
                  'stages. Incoming packet statistics confirm that encoded '
                  'video is arriving; a decoder is required to display '
                  'actual frames.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoPlaceholder(ThemeData theme) {
    final colors = theme.colorScheme;

    final String subtitle;
    if (_sessionState != HeadunitSessionState.connected) {
      subtitle = 'Waiting for an active Android Auto session';
    } else if (!_video.isSetup) {
      subtitle = 'Waiting for video AV setup';
    } else if (!_video.isStreaming) {
      subtitle = 'Video configured; waiting for stream start';
    } else if (_packetCount == 0) {
      subtitle = 'Stream started; waiting for H.264 packets';
    } else {
      subtitle = 'H.264 packets received; decoder not attached';
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
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            if (_packetCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$_packetCount packets · ${_formatBytes(_totalBytes)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ],
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
                  Text(
                    'Connected device',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(deviceSerial),
                  const SizedBox(height: 4),
                  Text(
                    state.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
                    ),
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
            _MetricRow(
              label: 'Video focus',
              value: focusMode,
            ),
            _MetricRow(
              label: 'Video session ID',
              value: sessionId?.toString() ?? '—',
            ),
            _MetricRow(
              label: 'Received packets',
              value: '$packetCount',
            ),
            _MetricRow(
              label: 'Encoded data',
              value: _formatBytes(totalBytes),
            ),
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

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.good,
  });

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
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
          ),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
  });

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
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}