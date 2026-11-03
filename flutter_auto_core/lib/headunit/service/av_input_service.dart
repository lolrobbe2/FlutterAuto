import 'package:flutter_auto_core/flutter_auto_core.dart';

/// Channel 7: microphone input to the phone.
///
/// This advertises PCM audio input. A microphone capture and streaming
/// implementation is still needed to send actual audio.
class AudioVisualService extends ChannelService {
  static const String serviceName = 'audio_visual';
  static const int defaultChannelId = 7;

  AudioVisualService() : super(channelId: defaultChannelId);

  @override
  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..avInputChannel = (AVInputChannel()
        ..streamType = MediaCodecType_Enum.MEDIA_CODEC_AUDIO_PCM
        ..audioConfig = (AudioConfig()
          ..sampleRate = 16000
          ..bitDepth = 16
          ..channelCount = 1));
  }

  @override
  Future<void> handleMessage(ProtocolMessage message) async {
    final id = messageIdOf(message);

    if (id == ControlMessage_Enum.CHANNEL_OPEN_REQUEST.value) {
      await _handleChannelOpenRequest(message);
      return;
    }

    log.warning(
      'AudioVisual Unhandled input message: '
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
