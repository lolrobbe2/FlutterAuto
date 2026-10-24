import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'ffmpeg_h264_decoder.dart';
import 'package:logging/logging.dart';

class FfmpegVideoView extends StatefulWidget {
  const FfmpegVideoView({super.key, required this.decoder});

  final FfmpegH264Decoder decoder;

  @override
  State<FfmpegVideoView> createState() => _FfmpegVideoViewState();
}

class _FfmpegVideoViewState extends State<FfmpegVideoView> {
  static const int _width = 800;
  static const int _height = 480;

  final Logger _log = Logger('FfmpegVideoView');

  StreamSubscription<Uint8List>? _frameSubscription;
  StreamSubscription<String>? _errorSubscription;

  ui.Image? _image;
  Uint8List? _pendingFrame;
  int? _pendingGeneration;

  int _generation = 0;
  int _receivedFrames = 0;
  int _renderedFrames = 0;

  bool _processingFrames = false;

  String _status = 'Waiting for decoded frames';
  String? _error;

  @override
  void initState() {
    super.initState();

    _log.info(
      'INIT: view=${identityHashCode(this)}, '
      'decoder=${identityHashCode(widget.decoder)}.',
    );

    _attachToDecoder();
  }

  @override
  void didUpdateWidget(covariant FfmpegVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.decoder != widget.decoder) {
      _log.info('Decoder changed; switching frame subscriptions.');

      _frameSubscription?.cancel();
      _errorSubscription?.cancel();

      _generation++;
      _pendingFrame = null;
      _pendingGeneration = null;

      final previous = _image;
      _image = null;
      previous?.dispose();

      _receivedFrames = 0;
      _renderedFrames = 0;
      _error = null;
      _status = 'Waiting for decoded frames';

      _attachToDecoder();

      setState(() {});
    }
  }

  void _attachToDecoder() {
    final generation = _generation;

    // Subscribe first so frames arriving during setup aren't missed.
    _frameSubscription = widget.decoder.frames.listen(
      (frame) => _handleRgbaFrame(frame, generation),
      onError: (Object error, StackTrace stackTrace) {
        _showError(
          error.toString(),
          generation,
          error: error,
          stackTrace: stackTrace,
        );
      },
      onDone: () {
        _log.warning('Decoder frame stream closed.');
      },
    );

    _errorSubscription = widget.decoder.errors.listen(
      (message) => _showError(message, generation),
    );

    // Broadcast streams don't replay. Restore the latest frame instead.
    final latest = widget.decoder.latestFrame;

    if (latest != null) {
      _log.info('Restoring latest decoded frame after view attachment.');
      _handleRgbaFrame(latest, generation);
    }
  }

  void _handleRgbaFrame(Uint8List rgba, int generation) {
    if (!mounted || generation != _generation) return;

    if (rgba.lengthInBytes != _width * _height * 4) {
      _log.severe(
        'Unexpected RGBA size: ${rgba.lengthInBytes}; '
        'expected ${_width * _height * 4}.',
      );
      return;
    }

    _receivedFrames++;

    if (_receivedFrames <= 3 || _receivedFrames % 60 == 0) {
      _log.fine('RGBA received #$_receivedFrames; rendered=$_renderedFrames.');
    }

    // Drop stale pending frames rather than letting rendering fall behind.
    _pendingFrame = rgba;
    _pendingGeneration = generation;

    if (!_processingFrames) {
      unawaited(_drainFrames());
    }
  }

  Future<void> _drainFrames() async {
    if (_processingFrames || !mounted) return;

    _processingFrames = true;

    try {
      while (mounted) {
        final rgba = _pendingFrame;
        final generation = _pendingGeneration;

        _pendingFrame = null;
        _pendingGeneration = null;

        if (rgba == null || generation == null) break;

        ui.ImmutableBuffer? buffer;
        ui.ImageDescriptor? descriptor;
        ui.Codec? codec;

        try {
          buffer = await ui.ImmutableBuffer.fromUint8List(rgba);

          descriptor = ui.ImageDescriptor.raw(
            buffer,
            width: _width,
            height: _height,
            pixelFormat: ui.PixelFormat.rgba8888,
            rowBytes: _width * 4,
          );

          codec = await descriptor.instantiateCodec();

          final frameInfo = await codec.getNextFrame();
          final decoded = frameInfo.image;

          // The view might have been replaced while conversion was running.
          if (!mounted || generation != _generation) {
            decoded.dispose();
            continue;
          }

          final previous = _image;

          setState(() {
            _image = decoded;
            _renderedFrames++;
            _status = 'Displaying video';
            _error = null;
          });

          if (_renderedFrames <= 3 || _renderedFrames % 60 == 0) {
            _log.fine(
              'RENDERED #$_renderedFrames: '
              '${decoded.width}x${decoded.height}.',
            );
          }

          if (previous != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              previous.dispose();
            });
          }
        } catch (error, stackTrace) {
          _showError(
            'Frame conversion failed: $error',
            generation,
            error: error,
            stackTrace: stackTrace,
          );
        } finally {
          codec?.dispose();
          descriptor?.dispose();
          buffer?.dispose();
        }
      }
    } finally {
      _processingFrames = false;

      if (mounted && _pendingFrame != null) {
        unawaited(_drainFrames());
      }
    }
  }

  void _showError(
    String message,
    int generation, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!mounted || generation != _generation) return;

    _log.severe(message, error, stackTrace);

    setState(() {
      _error = message;
      _status = 'Rendering error';
    });
  }

  @override
  void dispose() {
    _log.info(
      'DISPOSE VIEW: rendered=$_renderedFrames. '
      'The decoder remains owned by the parent.',
    );

    _generation++;

    _frameSubscription?.cancel();
    _errorSubscription?.cancel();

    _pendingFrame = null;
    _pendingGeneration = null;

    _image?.dispose();
    _image = null;

    // IMPORTANT: Do not dispose widget.decoder here.

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_image != null)
            RawImage(
              image: _image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.low,
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error == null)
                      const CircularProgressIndicator()
                    else
                      Icon(Icons.error_outline, color: colors.error, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      _error ?? _status,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
