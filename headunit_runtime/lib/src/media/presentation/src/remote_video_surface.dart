import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:headunit_shared/headunit_shared.dart';
import 'package:headunit_shared/headunit_shared_io.dart'
    show
        EncodedVideoFrame,
        MediaFrameSubscription,
        MediaStreamConnection,
        VideoStreamConfiguration;

import 'ffmpeg_video_decoder.dart';
import 'video_decoder.dart';

/// Displays an external application's decoded video surface and forwards
/// normalized pointer events to the remote application.
///
/// The widget owns its [VideoDecoder] but does not own or close the media
/// connection. Disposing the widget cancels its frame subscription, allowing
/// the app to be hidden without disconnecting its process or media session.
class RemoteVideoSurface extends StatefulWidget {
  final MediaStreamConnection connection;
  final VideoDecoderFactory? decoderFactory;
  final ValueChanged<ApplicationPointerEvent> onPointerEvent;
  final Widget? loading;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  const RemoteVideoSurface({
    super.key,
    required this.connection,
    this.decoderFactory,
    required this.onPointerEvent,
    this.loading,
    this.errorBuilder,
  });

  @override
  State<RemoteVideoSurface> createState() => _RemoteVideoSurfaceState();
}

class _RemoteVideoSurfaceState extends State<RemoteVideoSurface> {
  MediaFrameSubscription? _frameSubscription;
  VideoDecoder? _decoder;
  Object? _error;
  bool _loading = true;
  bool _disposed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize(_generation));
  }

  bool _isCurrent(int generation) {
    return mounted && !_disposed && generation == _generation;
  }

  Future<void> _initialize(int generation) async {
    MediaFrameSubscription? subscription;
    VideoDecoder? decoder;
    try {
      subscription = widget.connection.createFrameSubscription();
      _frameSubscription = subscription;
      final VideoDecoderFactory decoderFactory =
          widget.decoderFactory ?? FfmpegVideoDecoder.create;
      decoder = await decoderFactory(widget.connection.configuration);
      if (!_isCurrent(generation)) {
        await decoder.dispose();
        subscription.cancel();
        return;
      }

      // The player must not start until its Flutter surface is mounted. In
      // particular, FFplaySurface creates platform output resources that are
      // attached when buildView() enters the widget tree.
      _decoder = decoder;
      setState(() {
        _loading = false;
      });
      await WidgetsBinding.instance.endOfFrame;

      if (!_isCurrent(generation) || !identical(_decoder, decoder)) {
        await decoder.dispose();
        subscription.cancel();
        return;
      }

      if (decoder is StartableVideoDecoder) {
        await decoder.start();
      }
      await _consumeFrames(subscription, decoder, generation);
    } catch (error) {
      if (decoder != null) {
        if (identical(_decoder, decoder)) {
          _decoder = null;
        }
        await decoder.dispose();
      }
      subscription?.cancel();
      if (_isCurrent(generation)) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _consumeFrames(
    MediaFrameSubscription subscription,
    VideoDecoder decoder,
    int generation,
  ) async {
    while (_isCurrent(generation) && !subscription.isCancelled) {
      final EncodedVideoFrame? frame = await subscription.nextFrame();
      if (frame == null) {
        subscription.cancel();
        if (_isCurrent(generation) && identical(_decoder, decoder)) {
          _decoder = null;
          await decoder.dispose();
        }
        if (_isCurrent(generation)) {
          setState(() {
            _error = StateError('The remote video stream has ended.');
          });
        }
        return;
      }
      if (!_isCurrent(generation) || !identical(_decoder, decoder)) {
        return;
      }
      await decoder.decode(frame);
    }
  }

  @override
  void didUpdateWidget(covariant RemoteVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection != widget.connection ||
        oldWidget.decoderFactory != widget.decoderFactory) {
      _generation++;
      _frameSubscription?.cancel();
      _frameSubscription = null;
      final VideoDecoder? previousDecoder = _decoder;
      _decoder = null;
      if (previousDecoder != null) {
        unawaited(previousDecoder.dispose());
      }
      _error = null;
      _loading = true;
      unawaited(_initialize(_generation));
    }
  }

  void _handlePointer(
    PointerEvent event,
    ApplicationPointerPhase phase,
    Size surfaceSize,
  ) {
    if (!surfaceSize.width.isFinite ||
        !surfaceSize.height.isFinite ||
        surfaceSize.width <= 0.0 ||
        surfaceSize.height <= 0.0) {
      return;
    }

    // PointerEvent.localPosition is already transformed into the coordinate
    // space of the Listener that received the event. Using it avoids a
    // GlobalKey/RenderObject lookup during pointer dispatch and keeps the
    // coordinates correct if the shell applies transforms to the surface.
    final Offset localPosition = event.localPosition;
    final double x =
        (localPosition.dx / surfaceSize.width).clamp(0.0, 1.0).toDouble();
    final double y =
        (localPosition.dy / surfaceSize.height).clamp(0.0, 1.0).toDouble();
    final double pressureRange = event.pressureMax - event.pressureMin;
    final double? pressure = pressureRange > 0.0 && event.pressure.isFinite
        ? ((event.pressure - event.pressureMin) / pressureRange)
              .clamp(0.0, 1.0)
              .toDouble()
        : null;
    widget.onPointerEvent(
      ApplicationPointerEvent(
        pointerId: event.pointer,
        phase: phase,
        x: x,
        y: y,
        pressure: pressure,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Object? error = _error;
    if (error != null) {
      return widget.errorBuilder?.call(context, error) ??
          Center(child: Text('Unable to display application: $error'));
    }
    if (_loading || _decoder == null) {
      return widget.loading ?? const Center(child: SizedBox.shrink());
    }

    final VideoStreamConfiguration configuration =
        widget.connection.configuration;
    final bool quarterTurn =
        configuration.rotationDegrees == 90 ||
        configuration.rotationDegrees == 270;
    final double aspectRatio = quarterTurn
        ? configuration.height / configuration.width
        : configuration.width / configuration.height;
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size surfaceSize = constraints.biggest;
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (PointerDownEvent event) => _handlePointer(
                event,
                ApplicationPointerPhase.down,
                surfaceSize,
              ),
              onPointerMove: (PointerMoveEvent event) => _handlePointer(
                event,
                ApplicationPointerPhase.move,
                surfaceSize,
              ),
              onPointerUp: (PointerUpEvent event) => _handlePointer(
                event,
                ApplicationPointerPhase.up,
                surfaceSize,
              ),
              onPointerCancel: (PointerCancelEvent event) => _handlePointer(
                event,
                ApplicationPointerPhase.cancel,
                surfaceSize,
              ),
              child: _decoder!.buildView(),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _frameSubscription?.cancel();
    final VideoDecoder? decoder = _decoder;
    _decoder = null;
    if (decoder != null) {
      unawaited(decoder.dispose());
    }
    super.dispose();
  }
}
