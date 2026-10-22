import 'package:flutter_auto/generated/oaa/av/AVChannelData.pb.dart';
import 'package:flutter_auto/generated/oaa/av/MediaCodecTypeEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/generated/oaa/video/DisplayTypeEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/video/VideoConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/video/VideoFPSEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/video/VideoResolutionEnum.pb.dart';

class VideoService {
  static const String serviceName = 'video';
  static const int defaultChannelId = 3;

  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..avChannel = (AVChannel()
        ..streamType = MediaCodecType_Enum.MEDIA_CODEC_VIDEO_H264_BP
        ..displayId = 0
        ..displayType = DisplayType_Enum.MAIN
        ..videoConfigs.add(
          VideoConfig()
            ..codec = MediaCodecType_Enum.MEDIA_CODEC_VIDEO_H264_BP
            ..videoResolution = VideoResolution_Enum.VIDEO_800x480
            ..videoFps = VideoFPS_Enum.x30_
            ..marginWidth = 0
            ..marginHeight = 0
            ..dpi = 140,
        ));
  }

  Future<void> dispose() async {}
}
