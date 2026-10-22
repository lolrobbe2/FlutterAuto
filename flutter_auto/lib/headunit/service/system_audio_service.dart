import 'package:flutter_auto/generated/oaa/audio/AudioConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/audio/AudioTypeEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/av/AVChannelData.pb.dart';
import 'package:flutter_auto/generated/oaa/av/MediaCodecTypeEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';

AudioConfig _voiceAudioConfig() =>
    AudioConfig(sampleRate: 16000, bitDepth: 16, channelCount: 1);

class SystemAudioService {
  static const String serviceName = 'system_audio';
  static const int defaultChannelId = 6;

  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..avChannel = (AVChannel()
        ..streamType = MediaCodecType_Enum.MEDIA_CODEC_AUDIO_PCM
        ..audioType = AudioType_Enum.SYSTEM
        ..audioConfigs.add(_voiceAudioConfig()));
  }

  Future<void> dispose() async {}
}
