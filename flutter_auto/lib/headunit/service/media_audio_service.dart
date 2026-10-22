import 'package:flutter_auto/generated/oaa/audio/AudioConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/audio/AudioTypeEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/av/AVChannelData.pb.dart';
import 'package:flutter_auto/generated/oaa/av/MediaCodecTypeEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/headunit/service/channel_service.dart';

class MediaAudioService  extends ChannelService{
  static const String serviceName = 'media_audio';
  static const int defaultChannelId = 4;

  MediaAudioService(): super(channelId: defaultChannelId);

  
  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..avChannel = (AVChannel()
        ..streamType = MediaCodecType_Enum.MEDIA_CODEC_AUDIO_PCM
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
