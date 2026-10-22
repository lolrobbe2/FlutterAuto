import 'package:flutter_auto/generated/oaa/audio/AudioConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/av/AVInputChannelData.pb.dart';
import 'package:flutter_auto/generated/oaa/av/MediaCodecTypeEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/headunit/service/channel_service.dart';

AudioConfig _voiceAudioConfig() =>
    AudioConfig(sampleRate: 16000, bitDepth: 16, channelCount: 1);

/// Channel 7: microphone input to the phone.
///
/// This advertises PCM audio input. A microphone capture and streaming
/// implementation is still needed to send actual audio.
class MicrophoneInputService extends ChannelService {
  static const String serviceName = 'microphone_input';
  static const int defaultChannelId = 7;

  MicrophoneInputService(): super(channelId: defaultChannelId);

  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..avInputChannel = (AVInputChannel()
        ..streamType = MediaCodecType_Enum.MEDIA_CODEC_AUDIO_PCM
        ..audioConfig = _voiceAudioConfig());
  }
}
