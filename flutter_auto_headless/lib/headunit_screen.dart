import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_auto_core/flutter_auto_core.dart';
import 'package:flutter_auto_core/generated/oaa/input/ButtonCodeEnum.pbenum.dart';
import 'package:flutter_auto_core/headunit/drivers/input/pc_input_driver.dart';
import 'package:flutter_auto_core/headunit/input/input_button.dart';
import 'package:logging/logging.dart';

class HeadunitScreen extends StatefulWidget {
  const HeadunitScreen({
    super.key,
    required this.deviceSerial,
    required this.session,
    this.videoBuilder,
  });

  final String deviceSerial;
  final HeadunitSession session;

  /// Renders frames from the decoder owned by this screen.
  /// Do not start or dispose the decoder in this callback.
  final Widget Function(
    BuildContext context,
    FfmpegH264Decoder decoder,
  )? videoBuilder;

  @override
  State<HeadunitScreen> createState() => _HeadunitScreenState();
}

class _HeadunitScreenState extends State<HeadunitScreen> {
  final Logger _log = Logger('HeadunitScreen');

  late FfmpegH264Decoder _decoder;
  late TouchInput _touchInput;

  late InputButton _scrollUpButton;
  late InputButton _scrollDownButton;
  late InputButton _mouseBackButton;
  late InputButton _mouseForwardButton;

  String? _decoderError;

  VideoService get _video => widget.session.videoService;

  @override
  void initState() {
    super.initState();

    final dimensions = _video.resolution.dimensions;

    // Touch input.
    _touchInput = TouchInput(
      width: dimensions.width,
      height: dimensions.height,
    );
    widget.session.inputService.addInput(_touchInput);

    // PC mouse input buttons.
    _scrollUpButton = InputButton(ButtonCode_Enum.DPAD_UP);
    _scrollDownButton = InputButton(ButtonCode_Enum.DPAD_DOWN);
    _mouseBackButton =
        InputButton(ButtonCode_Enum.NAVIGATE_PREVIOUS);
    _mouseForwardButton =
        InputButton(ButtonCode_Enum.NAVIGATE_NEXT);

    // Register every button with the session so it is bound to the
    // underlying protocol channel before PcInputDriver sends events.
    widget.session.inputService.addInput(_scrollUpButton);
    widget.session.inputService.addInput(_scrollDownButton);
    widget.session.inputService.addInput(_mouseBackButton);
    widget.session.inputService.addInput(_mouseForwardButton);

    _decoder = FfmpegH264Decoder(
      width: dimensions.width,
      height: dimensions.height,
    );

    unawaited(_startDecoder());
    unawaited(_enterImmersiveMode());
  }

  Future<void> _enterImmersiveMode() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
    } catch (error, stackTrace) {
      _log.warning(
        'Could not enable immersive system UI mode.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _startDecoder() async {
    try {
      await _decoder.start(_video);

      if (!mounted) return;

      setState(() {
        _decoderError = null;
      });
    } catch (error, stackTrace) {
      _log.severe(
        'Failed to start the video decoder.',
        error,
        stackTrace,
      );

      if (!mounted) return;

      setState(() {
        _decoderError = error.toString();
      });
    }
  }

  @override
  void dispose() {
    unawaited(_decoder.dispose());

    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      ).catchError((Object error, StackTrace stackTrace) {
        _log.warning(
          'Could not restore system UI mode.',
          error,
          stackTrace,
        );
      }),
    );

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dimensions = _video.resolution.dimensions;
    final aspectRatio = dimensions.width / dimensions.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: PcInputDriver(
        scrollUpButton: _scrollUpButton,
        scrollDownButton: _scrollDownButton,
        mouseBackButton: _mouseBackButton,
        mouseForwardButton: _mouseForwardButton,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final availableHeight = constraints.maxHeight;

            // Fit the projection inside the window without stretching it.
            double width = availableWidth;
            double height = width / aspectRatio;

            if (height > availableHeight) {
              height = availableHeight;
              width = height * aspectRatio;
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: TouchInputDriver(
                      touchInput: _touchInput,
                      child: HeadunitVideoView(
                        resolution: _video.resolution,
                        decoder: _decoder,
                        videoBuilder: widget.videoBuilder,
                        borderRadius: 0,
                        backgroundColor: Colors.black,
                        showPlaceholder: true,
                      ),
                    ),
                  ),
                ),

                if (_decoderError != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Video decoder error: $_decoderError',
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}