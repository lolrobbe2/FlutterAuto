
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_auto/headunit/service/video_service.dart';
import 'package:flutter_auto/headunit/video/ffmpeg_h264_decoder.dart';

class FfmpegVideoView extends StatefulWidget {
  const FfmpegVideoView({
    super.key,
    required this.videoService,
  });

  final VideoService videoService;

  @override
  State<FfmpegVideoView> createState() => _FfmpegVideoViewState();
}

class _FfmpegVideoViewState extends State<FfmpegVideoView> {
  static const int _width = 800;
  static const int _height = 480;

  late final FfmpegH264Decoder _decoder;

  StreamSubscription<Uint8List>? _frameSubscription;
  StreamSubscription<String>? _errorSubscription;

  ui.Image? _image;
  Uint8List? _pendingFrame;

  String _status = 'Starting bundled FFmpeg decoder…';
  String? _error;

  bool _decodingFrame = false;
  int _decodedFrames = 0;

  @override
  void initState() {
    super.initState();

    _decoder = FfmpegH264Decoder(
      width: _width,
      height: _height,
    );

    // Subscribe before starting the decoder to avoid missing early frames.
    _frameSubscription = _decoder.frames.listen(
      _handleRgbaFrame,
      onError: (Object error) => _showError(error.toString()),
    );

    _errorSubscription = _decoder.errors.listen(_showError);

    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _decoder.start(widget.videoService);

      if (!mounted) return;

      // Don't overwrite a status updated by an already-decoded frame.
      if (_decodedFrames == 0 && _error == null) {
        setState(() {
          _status = 'Decoder running; waiting for video frames…';
        });
      }
    } catch (error) {
      _showError(error.toString());
    }
  }

  void _handleRgbaFrame(Uint8List rgba) {
    if (!mounted) return;

    // Keep only the newest pending frame while an image is being created.
    if (_decodingFrame) {
      _pendingFrame = rgba;
      return;
    }

    _decodeFrame(rgba);
  }

  void _decodeFrame(Uint8List rgba) {
    _decodingFrame = true;

    ui.decodeImageFromPixels(
      rgba,
      _width,
      _height,
      ui.PixelFormat.rgba8888,
      (ui.Image decoded) {
        if (!mounted) {
          decoded.dispose();
          _decodingFrame = false;
          _pendingFrame = null;
          return;
        }

        final previous = _image;

        setState(() {
          _image = decoded;
          _decodedFrames++;
          _status = 'Displaying video';
          _error = null;
        });

        if (previous != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            previous.dispose();
          });
        }

        _decodingFrame = false;

        // Immediately display the latest frame queued during conversion.
        final nextFrame = _pendingFrame;
        _pendingFrame = null;

        if (nextFrame != null) {
          _decodeFrame(nextFrame);
        }
      },
      rowBytes: _width * 4,
    );
  }

  void _showError(String error) {
    if (!mounted) return;

    setState(() {
      _error = error;
      _status = 'Decoder error';
    });
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    _errorSubscription?.cancel();

    _pendingFrame = null;

    final image = _image;
    _image = null;
    image?.dispose();

    unawaited(_decoder.dispose());

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
                      Icon(
                        Icons.error_outline,
                        color: colors.error,
                        size: 40,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      _error == null ? _status : 'Unable to decode video',
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: colors.error,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                child: Text(
                  '$_decodedFrames frames · $_status',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
