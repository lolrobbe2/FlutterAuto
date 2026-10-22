import 'package:flutter_auto/generated/oaa/audio/AudioConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/av/AVInputChannelData.pb.dart';
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

    log.info('Microphone channel $channelId opened successfully.');
  }
}
