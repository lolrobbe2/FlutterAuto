import 'package:flutter_auto/generated/oaa/audio/AudioConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/audio/AudioTypeEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/av/AVChannelData.pb.dart';
import 'package:flutter_auto/generated/oaa/av/MediaCodecTypeEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/common/StatusEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelOpenRequestMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelOpenResponseMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ControlMessageIdsEnum.pbenum.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';
import 'package:flutter_auto/headunit/protocol_message.dart';
import 'package:flutter_auto/headunit/service/channel_service.dart';

AudioConfig _voiceAudioConfig() =>
    AudioConfig(sampleRate: 16000, bitDepth: 16, channelCount: 1);

/// Channel 5: navigation speech and assistant voice.
class SpeechAudioService extends ChannelService {
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
  @override
  Future<void> handleMessage(ProtocolMessage message) async {
    final id = messageIdOf(message);

    if (id == ControlMessage_Enum.CHANNEL_OPEN_REQUEST.value) {
      await _handleChannelOpenRequest(message);
      return;
    }

    log.fine(
      'Unhandled input message: '
      '0x${id.toRadixString(16).padLeft(4, '0')}',
    );
  }

  Future<void> _handleChannelOpenRequest(ProtocolMessage message) async {
    ChannelOpenRequest request = ChannelOpenRequest.fromBuffer(bodyOf(message));
    if (request.channelId != channelId) {
      log.warning(
        'Ignoring channel-open request for channel ${request.channelId}; '
        'this service owns channel $channelId.',
      );
      return;
    }
    final response = ChannelOpenResponse(status: Status_Enum.OK);
    await sendMessage(
      messageId: ControlMessage_Enum.CHANNEL_OPEN_RESPONSE.value,
      body: response.writeToBuffer(),
      encryptionType: EncryptionType.encrypted,
      messageType: MessageType.control,
    );

    log.info('Speech Audio channel $channelId opened successfully.');
  }
}
