import 'package:flutter/material.dart';
import '../../generated/oaa/video/VideoResolutionEnum.pbenum.dart';
import 'ffmpeg_h264_decoder.dart';
import 'video_message_id.dart';

class HeadunitVideoView extends StatelessWidget {
  const HeadunitVideoView({
    super.key,
    required this.resolution,
    required this.decoder,
    this.videoBuilder,
    this.borderRadius = 12,
    this.backgroundColor = Colors.black,
    this.showPlaceholder = true,
  });

  final VideoResolution_Enum resolution;
  final FfmpegH264Decoder decoder;

  final Widget Function(
    BuildContext context,
    FfmpegH264Decoder decoder,
  )? videoBuilder;

  final double borderRadius;
  final Color backgroundColor;
  final bool showPlaceholder;

  @override
  Widget build(BuildContext context) {
    final VideoDimensions dimensions = resolution.dimensions;

    if (dimensions.width == 0 || dimensions.height == 0) {
      return const Center(
        child: Text('No video resolution selected'),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ColoredBox(
        color: backgroundColor,
        child: AspectRatio(
          aspectRatio: dimensions.width / dimensions.height,
          child: videoBuilder?.call(context, decoder) ??
              (showPlaceholder
                  ? const Center(
                      child: Icon(
                        Icons.ondemand_video,
                        color: Colors.white70,
                        size: 48,
                      ),
                    )
                  : const SizedBox.expand()),
        ),
      ),
    );
  }
}
