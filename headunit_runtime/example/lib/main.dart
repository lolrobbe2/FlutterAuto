import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:headunit_contracts/headunit_contracts.dart';
import 'package:headunit_runtime/headunit_runtime.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const RuntimeExampleApp());
}

class RuntimeExampleApp extends StatelessWidget {
  const RuntimeExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Headunit Runtime Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const RuntimeExamplePage(),
    );
  }
}

class RuntimeExamplePage extends StatefulWidget {
  const RuntimeExamplePage({super.key});

  @override
  State<RuntimeExamplePage> createState() =>
      _RuntimeExamplePageState();
}

class _RuntimeExamplePageState extends State<RuntimeExamplePage> {
  final HeadunitRuntime _runtime = HeadunitRuntime();

  AudioService? _audioService;

  AudioSession? _activeSession;
  AudioStream? _activeStream;

  int _nextStreamId = 1;

  bool _initializing = true;
  bool _shuttingDown = false;

  String _status = 'Initializing runtime...';

  @override
  void initState() {
    super.initState();
    _initializeRuntime();
  }

  Future<void> _initializeRuntime() async {
    try {
      await _runtime.initialize();

      final ApplicationLaunchContext launchContext =
          ApplicationLaunchContext(
        applicationId: ApplicationId(
          'com.example.runtime_example',
        ),
        grantedCapabilities: [
          CapabilityId('audio.sessions.manage'),
        ],
        productId: 'runtime_example',
        locale: 'en',
      );

      final ServiceBroker broker =
          _runtime.createServiceBroker(launchContext);

      final AudioService audioService =
          broker.getService(AudioService.serviceKey);

      if (!mounted) {
        return;
      }

      setState(() {
        _audioService = audioService;
        _initializing = false;
        _status = 'Runtime initialized successfully.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _initializing = false;
        _status = 'Initialization failed: $error';
      });
    }
  }

  void _createSession() {
    final AudioService? audioService = _audioService;

    if (audioService == null) {
      return;
    }

    final AudioSession session = audioService.createSession();

    setState(() {
      _activeSession = session;
      _activeStream = null;
      _nextStreamId = 1;
      _status = 'Created audio session ${session.id}.';
    });
  }

  void _createAndPlayTestTone() {
    final AudioSession? session = _activeSession;

    if (session == null) {
      return;
    }

    final AudioStreamId streamId =
        AudioStreamId(_nextStreamId++);

    try {
      final AudioStream stream = session.createStream(
        id: streamId,
        configuration: AudioStreamConfiguration(
          sampleRate: 48000,
          channels: AudioChannelLayout.stereo,
          format: AudioSampleFormat.signed16LittleEndian,
        ),
      );

      // Start playback, feed PCM data and then signal end-of-data.
      stream.play();
      stream.appendData(_generateTestTone());
      stream.finish();

      setState(() {
        _activeStream = stream;
        _status = 'Playing test tone on stream ${stream.id}.';
      });
    } catch (error) {
      setState(() {
        _status = 'Failed to create stream: $error';
      });
    }
  }

  void _pauseStream() {
    final AudioStream? stream = _activeStream;

    if (stream == null) {
      return;
    }

    try {
      stream.pause();

      setState(() {
        _status = 'Stream ${stream.id} paused.';
      });
    } catch (error) {
      setState(() {
        _status = 'Pause failed: $error';
      });
    }
  }

  void _resumeStream() {
    final AudioStream? stream = _activeStream;

    if (stream == null) {
      return;
    }

    try {
      stream.resume();

      setState(() {
        _status = 'Stream ${stream.id} resumed.';
      });
    } catch (error) {
      setState(() {
        _status = 'Resume failed: $error';
      });
    }
  }

  Future<void> _stopStream() async {
    final AudioStream? stream = _activeStream;
    final AudioSession? session = _activeSession;

    if (stream == null || session == null) {
      return;
    }

    try {
      await session.removeStream(stream.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _activeStream = null;
        _status = 'Stream ${stream.id} removed.';
      });
    } catch (error) {
      setState(() {
        _status = 'Failed to remove stream: $error';
      });
    }
  }

  Future<void> _removeSession() async {
    final AudioSession? session = _activeSession;
    final AudioService? audioService = _audioService;

    if (session == null || audioService == null) {
      return;
    }

    try {
      await audioService.removeSession(session.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _activeSession = null;
        _activeStream = null;
        _status = 'Session ${session.id} removed.';
      });
    } catch (error) {
      setState(() {
        _status = 'Failed to remove session: $error';
      });
    }
  }

  Future<void> _testPermissionDenial() async {
    try {
      final ServiceBroker restrictedBroker =
          _runtime.createServiceBroker(
        ApplicationLaunchContext(
          applicationId: ApplicationId(
            'com.example.restricted_app',
          ),
        ),
      );

      restrictedBroker.getService(AudioService.serviceKey);

      setState(() {
        _status = 'Unexpected: restricted access was granted.';
      });
    } on ServiceAccessDeniedException {
      setState(() {
        _status = 'Permission test passed: audio access denied.';
      });
    } catch (error) {
      setState(() {
        _status = 'Permission test failed: $error';
      });
    }
  }

  Future<void> _shutdownRuntime() async {
    if (_shuttingDown) {
      return;
    }

    setState(() {
      _shuttingDown = true;
      _status = 'Shutting down runtime...';
    });

    try {
      await _runtime.dispose();

      if (!mounted) {
        return;
      }

      setState(() {
        _audioService = null;
        _activeSession = null;
        _activeStream = null;
        _status = 'Runtime disposed.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Shutdown failed: $error';
      });
    }
  }

  Uint8List _generateTestTone() {
    const int sampleRate = 48000;
    const int channels = 2;
    const int durationSeconds = 8;
    const double frequency = 440;
    const double amplitude = 0.15;

    final int frameCount = sampleRate * durationSeconds;

    final ByteData data = ByteData(
      frameCount * channels * 2,
    );

    for (int frame = 0; frame < frameCount; frame++) {
      final double time = frame / sampleRate;

      final double wave = math.sin(
        2 * math.pi * frequency * time,
      );

      final int sample = (wave * amplitude * 32767).round();

      final int offset = frame * channels * 2;

      data.setInt16(offset, sample, Endian.little);
      data.setInt16(offset + 2, sample, Endian.little);
    }

    return data.buffer.asUint8List();
  }

  @override
  void dispose() {
    unawaited(_runtime.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int sessionCount =
        _audioService?.sessions.length ?? 0;

    final int streamCount =
        _activeSession?.streams.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Headunit Runtime Example'),
        actions: [
          IconButton(
            tooltip: 'Shutdown runtime',
            onPressed: _audioService == null || _shuttingDown
                ? null
                : _shutdownRuntime,
            icon: const Icon(Icons.power_settings_new),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildRuntimeCard(),
          const SizedBox(height: 16),
          _buildServiceCard(sessionCount),
          const SizedBox(height: 16),
          _buildSessionCard(streamCount),
          const SizedBox(height: 16),
          _buildStreamCard(),
          const SizedBox(height: 16),
          _buildPermissionCard(),
          const SizedBox(height: 16),
          _buildStatusCard(),
        ],
      ),
    );
  }

  Widget _buildRuntimeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Runtime',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('State'),
                const Spacer(),
                Text(_runtime.state.name),
              ],
            ),
            const SizedBox(height: 12),
            if (_initializing)
              const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceCard(int sessionCount) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Service Broker',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text('Application: com.example.runtime_example'),
            const SizedBox(height: 4),
            Text('Audio service available: ${_audioService != null}'),
            Text('Registered sessions: $sessionCount'),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(int streamCount) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Audio Sessions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              _activeSession == null
                  ? 'No active session'
                  : 'Active session: ${_activeSession!.id}',
            ),
            Text('Streams in session: $streamCount'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _audioService == null
                      ? null
                      : _createSession,
                  icon: const Icon(Icons.add),
                  label: const Text('Create session'),
                ),
                OutlinedButton.icon(
                  onPressed: _activeSession == null
                      ? null
                      : _removeSession,
                  icon: const Icon(Icons.delete),
                  label: const Text('Remove session'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Audio Streams',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              _activeStream == null
                  ? 'No active stream'
                  : 'Active stream: ${_activeStream!.id}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _activeSession == null ||
                          _shuttingDown
                      ? null
                      : _createAndPlayTestTone,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play test tone'),
                ),
                OutlinedButton.icon(
                  onPressed: _activeStream == null
                      ? null
                      : _pauseStream,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
                OutlinedButton.icon(
                  onPressed: _activeStream == null
                      ? null
                      : _resumeStream,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume'),
                ),
                OutlinedButton.icon(
                  onPressed: _activeStream == null
                      ? null
                      : _stopStream,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop and remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Permission Test',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Try retrieving AudioService from a broker '
              'without audio.sessions.manage.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _audioService == null
                  ? null
                  : _testPermissionDenial,
              icon: const Icon(Icons.security),
              label: const Text('Test permission denial'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(_status),
          ],
        ),
      ),
    );
  }
}