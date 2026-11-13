$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$branch = git -C $repoRoot branch --show-current
if ($branch -ne 'main') {
    throw "This integration patch must be applied on the merged main branch. Current branch: '$branch'."
}
$mainPath = Join-Path $repoRoot 'headunit_runtime\example\lib\main.dart'
$pubspecPath = Join-Path $repoRoot 'headunit_runtime\example\pubspec.yaml'

if (-not (Test-Path $mainPath)) {
    throw "Could not find $mainPath. Extract this patch into the FlutterAuto repository root."
}
if (-not (Test-Path $pubspecPath)) {
    throw "Could not find $pubspecPath. Extract this patch into the FlutterAuto repository root."
}

function Replace-ExactlyOnce {
    param(
        [string]$Text,
        [string]$Old,
        [string]$New,
        [string]$Description
    )

    $count = [regex]::Matches($Text, [regex]::Escape($Old)).Count
    if ($count -ne 1) {
        throw "Expected exactly one occurrence for '$Description', found $count. No files have been written yet."
    }

    return $Text.Replace($Old, $New)
}

$main = [System.IO.File]::ReadAllText($mainPath).Replace("`r`n", "`n")

$main = Replace-ExactlyOnce $main `
    "import 'runtime_example_application.dart';" `
    "import 'runtime_example_application.dart';`nimport 'media_demo/remote_video_demo_controller.dart';" `
    'demo controller import'

$main = Replace-ExactlyOnce $main `
    "  Widget? _managedApplicationWidget;`n  AudioService? _audioService;" `
    "  Widget? _managedApplicationWidget;`n  AudioService? _audioService;`n`n  RemoteVideoDemoController? _remoteVideoDemo;`n  bool _startingRemoteVideoDemo = false;" `
    'demo state fields'

$demoMethods = @'
  Future<void> _startRemoteVideoDemo() async {
    if (_startingRemoteVideoDemo ||
        _remoteVideoDemo != null ||
        _shuttingDown) {
      return;
    }

    setState(() {
      _startingRemoteVideoDemo = true;
      _status = 'Starting authenticated H.264 media demo...';
    });

    RemoteVideoDemoController? demo;
    try {
      final RemoteVideoDemoController createdDemo =
          await RemoteVideoDemoController.create();
      demo = createdDemo;
      if (!mounted) {
        await createdDemo.dispose();
        return;
      }

      setState(() {
        _remoteVideoDemo = createdDemo;
        _startingRemoteVideoDemo = false;
        _status = 'H.264 sender connected. Starting FFplay decoder...';
      });
      // Mount the RemoteVideoSurface first. Its frame subscription is created
      // during initState; it then mounts FFplaySurface before starting FFplay.
      // The bounded receiver queue protects the brief setup interval.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          _shuttingDown ||
          !identical(_remoteVideoDemo, createdDemo)) {
        await createdDemo.dispose();
        return;
      }
      createdDemo.start();
    } catch (error) {
      await demo?.dispose();
      if (!mounted) {
        return;
      }
      setState(() {
        _startingRemoteVideoDemo = false;
        _status = 'Remote video demo failed: $error';
      });
    }
  }

  Future<void> _stopRemoteVideoDemo() async {
    final RemoteVideoDemoController? demo = _remoteVideoDemo;
    if (demo == null) {
      return;
    }

    setState(() {
      _remoteVideoDemo = null;
      _status = 'Stopping remote video demo...';
    });

    // Unmount RemoteVideoSurface first so it releases FFplay's process-wide
    // surface before the media connection is closed.
    await WidgetsBinding.instance.endOfFrame;
    await demo.dispose();

    if (mounted) {
      setState(() {
        _status = 'Remote video demo stopped.';
      });
    }
  }

  void _handleRemoteVideoPointer(ApplicationPointerEvent event) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'Remote pointer ${event.phase.name}: '
          '${(event.x * 100).toStringAsFixed(1)}%, '
          '${(event.y * 100).toStringAsFixed(1)}%';
    });
  }

  Widget _buildRemoteVideoDemoCard() {
    final RemoteVideoDemoController? demo = _remoteVideoDemo;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Remote video · FFmpegKit',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'A synthetic H.264 application stream sent through the '
              'authenticated media transport and rendered by FFplay.',
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: const Color(0xFF101820),
                child: demo == null
                    ? const Center(
                        child: Text('Start the demo to display remote video'),
                      )
                    : RemoteVideoSurface(
                        connection: demo.connection,
                        onPointerEvent: _handleRemoteVideoPointer,
                        loading: const Center(
                          child: CircularProgressIndicator(),
                        ),
                        errorBuilder: (BuildContext context, Object error) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'FFplay could not display the stream:\n$error',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            if (demo != null) ...[
              const SizedBox(height: 8),
              ValueListenableBuilder<int>(
                valueListenable: demo.framesSent,
                builder: (BuildContext context, int count, Widget? child) {
                  return Text('Access units sent: $count');
                },
              ),
              ValueListenableBuilder<Object?>(
                valueListenable: demo.error,
                builder: (BuildContext context, Object? error, Widget? child) {
                  if (error == null) {
                    return const SizedBox.shrink();
                  }
                  return Text('Sender error: $error');
                },
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: demo != null ||
                          _startingRemoteVideoDemo ||
                          _shuttingDown
                      ? null
                      : _startRemoteVideoDemo,
                  icon: _startingRemoteVideoDemo
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(
                    _startingRemoteVideoDemo ? 'Starting...' : 'Start video demo',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: demo == null ? null : _stopRemoteVideoDemo,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop video demo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

'@

$main = Replace-ExactlyOnce $main `
    "  void _createSession() {" `
    ($demoMethods + "  void _createSession() {") `
    'remote video demo methods'

$main = Replace-ExactlyOnce $main `
    "          _buildManagedApplicationCard()," `
    "          _buildManagedApplicationCard(),`n          const SizedBox(height: 16),`n          _buildRemoteVideoDemoCard()," `
    'remote video demo card placement'

$main = Replace-ExactlyOnce $main `
    "      await _runtime.dispose();" `
    "      await _stopRemoteVideoDemo();`n      await _runtime.dispose();" `
    'runtime shutdown demo cleanup'

$main = Replace-ExactlyOnce $main `
    "  @override`n  void dispose() {`n    unawaited(_runtime.dispose());`n    super.dispose();`n  }" `
    "  @override`n  void dispose() {`n    final RemoteVideoDemoController? demo = _remoteVideoDemo;`n    _remoteVideoDemo = null;`n    if (demo != null) {`n      unawaited(demo.dispose());`n    }`n    unawaited(_runtime.dispose());`n    super.dispose();`n  }" `
    'widget disposal cleanup'

$pubspec = [System.IO.File]::ReadAllText($pubspecPath).Replace("`r`n", "`n")
$pubspec = Replace-ExactlyOnce $pubspec `
    "  uses-material-design: true" `
    "  uses-material-design: true`n  assets:`n    - assets/remote_video_demo.h264" `
    'demo video asset declaration'

$encoding = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($mainPath, $main, $encoding)
[System.IO.File]::WriteAllText($pubspecPath, $pubspec, $encoding)

Write-Host 'Remote video demo integrated into headunit_runtime/example.' -ForegroundColor Green
Write-Host 'Next: cd headunit_runtime/example; flutter pub get; flutter run -d windows' -ForegroundColor Cyan
