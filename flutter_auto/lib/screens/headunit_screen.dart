import 'package:flutter/material.dart';
import 'package:flutter_auto/headunit/headunit_session.dart';

class HeadunitServerScreen extends StatelessWidget {
  const HeadunitServerScreen({
    super.key,
    required this.deviceSerial,
    required this.session,
  });

  final String deviceSerial;
  final HeadunitSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Android Auto Head Unit'),
      ),
      body: SafeArea(
        child: StreamBuilder<HeadunitSessionState>(
          stream: session.states,
          initialData: session.state,
          builder: (context, snapshot) {
            final state = snapshot.data ?? session.state;
            final status = _statusFor(state, theme.colorScheme);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Connection status
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: status.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            status.icon,
                            color: status.color,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                status.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                status.description,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (state == HeadunitSessionState.connecting ||
                                  state ==
                                      HeadunitSessionState.negotiatingVersion)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: LinearProgressIndicator(),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Device information
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Head unit',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _InfoRow(
                          icon: Icons.devices,
                          label: 'Device serial',
                          value: deviceSerial,
                        ),
                        const SizedBox(height: 8),
                        _InfoRow(
                          icon: Icons.lan,
                          label: 'Session state',
                          value: state.name,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'Android Auto display',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),

                // Future video rendering surface. Keep this area dedicated
                // to the projected image rather than connection diagnostics.
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    color: Colors.black,
                    child: AspectRatio(
                      aspectRatio: 800 / 480,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.ondemand_video,
                                size: 54,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Video output will appear here',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                state == HeadunitSessionState.connected
                                    ? 'Session connected. Waiting for video setup and frames.'
                                    : 'Waiting for an Android Auto session.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'The session status and video status are separate. '
                  'The display will become active when the video channel '
                  'is negotiated and frames are decoded.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  _SessionStatus _statusFor(
    HeadunitSessionState state,
    ColorScheme colors,
  ) {
    switch (state) {
      case HeadunitSessionState.disconnected:
        return _SessionStatus(
          title: 'Disconnected',
          description: 'No Android Auto session is active.',
          color: colors.outline,
          icon: Icons.link_off,
        );

      case HeadunitSessionState.connecting:
        return _SessionStatus(
          title: 'Connecting',
          description: 'Preparing ADB forwarding and opening the connection.',
          color: colors.primary,
          icon: Icons.sync,
        );

      case HeadunitSessionState.negotiatingVersion:
        return _SessionStatus(
          title: 'Negotiating session',
          description:
              'Protocol negotiation, TLS, authentication, and service discovery.',
          color: colors.primary,
          icon: Icons.sync_lock,
        );

      case HeadunitSessionState.connected:
        return _SessionStatus(
          title: 'Session connected',
          description:
              'Protocol setup completed. Video projection may still need to start.',
          color: colors.tertiary,
          icon: Icons.check_circle_outline,
        );

      case HeadunitSessionState.disconnecting:
        return _SessionStatus(
          title: 'Disconnecting',
          description: 'Closing the Android Auto session.',
          color: colors.secondary,
          icon: Icons.link_off,
        );

      case HeadunitSessionState.failed:
        return _SessionStatus(
          title: 'Connection failed',
          description: 'Check the session logs for the underlying error.',
          color: colors.error,
          icon: Icons.error_outline,
        );
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 12),
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
    );
  }
}

class _SessionStatus {
  const _SessionStatus({
    required this.title,
    required this.description,
    required this.color,
    required this.icon,
  });

  final String title;
  final String description;
  final Color color;
  final IconData icon;
}