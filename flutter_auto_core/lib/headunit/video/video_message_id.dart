// TODO Implement this library.
import 'package:flutter/material.dart';
import '../../generated/oaa/video/VideoResolutionEnum.pbenum.dart';
import 'ffmpeg_h264_decoder.dart';

// Import the generated protobuf enum from your project.

enum VideoMessageId {
  channelOpenRequest(0x0007),
  channelOpenResponse(0x0008),

  avChannelSetupRequest(0x8000),
  avChannelStartIndication(0x8001),
  avChannelStopIndication(0x8002),
  avChannelSetupResponse(0x8003),
  avMediaAckIndication(0x8004),

  videoFocusRequest(0x8007),
  videoFocusIndication(0x8008),

  mediaWithTimestamp(0x0000),
  media(0x0001);

  const VideoMessageId(this.value);

  final int value;

  static VideoMessageId? fromValue(int value) {
    for (final id in VideoMessageId.values) {
      if (id.value == value) {
        return id;
      }
    }
    return null;
  }
}

typedef VideoDimensions = ({int width, int height});

extension VideoResolutionDimensions on VideoResolution_Enum {
  VideoDimensions get dimensions {
    switch (this) {
      case VideoResolution_Enum.NONE:
        return (width: 0, height: 0);
      case VideoResolution_Enum.VIDEO_800x480:
        return (width: 800, height: 480);
      case VideoResolution_Enum.VIDEO_1280x720:
        return (width: 1280, height: 720);
      case VideoResolution_Enum.VIDEO_1920x1080:
        return (width: 1920, height: 1080);
      case VideoResolution_Enum.VIDEO_2560x1440:
        return (width: 2560, height: 1440);
      case VideoResolution_Enum.VIDEO_3840x2160:
        return (width: 3840, height: 2160);
      case VideoResolution_Enum.VIDEO_720x1280:
        return (width: 720, height: 1280);
      case VideoResolution_Enum.VIDEO_1080x1920:
        return (width: 1080, height: 1920);
      case VideoResolution_Enum.VIDEO_1440x2560:
        return (width: 1440, height: 2560);
      case VideoResolution_Enum.VIDEO_2160x3840:
        return (width: 2160, height: 3840);
    }
    return (width: 0, height: 0);
  }
}
