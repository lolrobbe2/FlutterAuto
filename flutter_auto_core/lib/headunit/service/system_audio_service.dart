import 'package:flutter_auto_core/flutter_auto_core.dart';

AudioConfig _voiceAudioConfig() =>
    AudioConfig(sampleRate: 16000, bitDepth: 16, channelCount: 1);

class SystemAudioService extends ChannelService {
  static const String serviceName = 'system_audio';
  static const int defaultChannelId = 6;

  SystemAudioService() : super(channelId: defaultChannelId);

  @override
  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..avChannel = (AVChannel()
        ..streamType = MediaCodecType_Enum.MEDIA_CODEC_AUDIO_PCM
        ..audioType = AudioType_Enum.SYSTEM
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
      'System Audio Unhandled input message: '
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

    log.info('System Audio channel $channelId opened successfully.');
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
