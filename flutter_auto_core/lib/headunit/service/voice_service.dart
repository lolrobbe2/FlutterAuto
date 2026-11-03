import 'package:flutter_auto_core/oaa/export.dart';

import '../protocol_frame.dart';
import '../protocol_message.dart';
import 'channel_service.dart';

AudioConfig _voiceAudioConfig() =>
    AudioConfig(sampleRate: 48000, bitDepth: 16, channelCount: 1);

/// Channel 5: navigation speech and assistant voice.
class SpeechAudioService extends ChannelService {
  static const String serviceName = 'speech_audio';
  static const int defaultChannelId = 5;

  SpeechAudioService() : super(channelId: defaultChannelId);

  @override
  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..avChannel = (AVChannel()
        ..streamType = MediaCodecType_Enum.MEDIA_CODEC_AUDIO_PCM
        ..audioType = AudioType_Enum.SPEECH
        ..audioConfigs.add(_voiceAudioConfig()));
  }

  @override
  Future<void> dispose() async {}
  @override
  Future<void> handleMessage(ProtocolMessage message) async {
    final id = messageIdOf(message);

    if (id == ControlMessage_Enum.CHANNEL_OPEN_REQUEST.value) {
      await _handleChannelOpenRequest(message);
      return;
    }
    if (id == AVChannelMessage_Enum.SETUP_REQUEST.value) {
      await _handleSetupRequest(message);
      return;
    }

    log.warning(
      'Speech Audio Unhandled input message: '
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

  Future<void> _handleSetupRequest(ProtocolMessage message) async {
    AVChannelSetupRequest request = AVChannelSetupRequest.fromBuffer(
      bodyOf(message),
    );
    request.mediaCodecType;
    final response = AVChannelSetupResponse(
      mediaStatus: AVChannelSetupStatus_Enum.OK,
      maxUnacked: 10,
      configs: [0],
    );
    await sendMessage(
      messageId: AVChannelMessage_Enum.SETUP_RESPONSE.value,
      body: response.writeToBuffer(),
      encryptionType: EncryptionType.encrypted,
      messageType: MessageType.specific,
    );
  }
}
