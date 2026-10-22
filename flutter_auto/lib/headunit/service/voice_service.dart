import 'package:flutter_auto/generated/oaa/audio/AudioConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/audio/AudioTypeEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/av/AVChannelData.pb.dart';
import 'package:flutter_auto/generated/oaa/av/MediaCodecTypeEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/headunit/service/channel_service.dart';

AudioConfig _voiceAudioConfig() =>
    AudioConfig(sampleRate: 16000, bitDepth: 16, channelCount: 1);

/// Channel 5: navigation speech and assistant voice.
class SpeechAudioService extends ChannelService{
  static const String serviceName = 'speech_audio';
  static const int defaultChannelId = 5;

  SpeechAudioService() : super(channelId: defaultChannelId);

  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..avChannel = (AVChannel()
        ..streamType = MediaCodecType_Enum.MEDIA_CODEC_AUDIO_PCM
        ..audioType = AudioType_Enum.SPEECH
        ..audioConfigs.add(_voiceAudioConfig()));
  }

  Future<void> dispose() async {}
}
