import 'package:flutter_auto/generated/oaa/audio/AudioConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/audio/AudioTypeEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/av/AVChannelData.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';

class MediaAudioService {
  static const String serviceName = 'media_audio';
  static const int defaultChannelId = 4;

  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..avChannel = (AVChannel()
        ..audioType = AudioType_Enum.MEDIA
        ..audioConfigs.add(
          AudioConfig()
            ..sampleRate = 48000
            ..bitDepth = 16
            ..channelCount = 2,
        ));
  }

  Future<void> dispose() async {}
}
