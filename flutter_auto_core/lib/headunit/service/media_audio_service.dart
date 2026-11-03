import 'dart:typed_data';

import 'package:flutter_auto_core/flutter_auto_core.dart';
import 'package:flutter_auto_core/headunit/audio/audio_stream.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

//AUDIO_SINK_SYSTEM
class MediaAudioService extends ChannelService {
  static const String serviceName = 'media_audio';
  static const int defaultChannelId = 4;
  int session = -1;
  AudioStream? currentStream;
  MediaAudioService() : super(channelId: defaultChannelId);

  @override
  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..avChannel = (AVChannel()
        ..streamType = MediaCodecType_Enum.MEDIA_CODEC_AUDIO_PCM
        ..audioType = AudioType_Enum.MEDIA
        ..audioConfigs.add(
          AudioConfig()
            ..sampleRate = 48000
            ..bitDepth = 32
            ..channelCount = 2,
        ));
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
    if (id == AVChannelMessage_Enum.START_INDICATION.value) {
      await _handleStartIndication(message);
      return;
    }
    if (id == AVChannelMessage_Enum.STOP_INDICATION.value) {
      await _handleStopIndication(message);
      return;
    }

    if (id == AVChannelMessage_Enum.AV_MEDIA_WITH_TIMESTAMP_INDICATION.value) {
      await _handleMediaWithTimeStampIndication(message);
    }

    log.warning(
      'MediaAudio Unhandled input message: '
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

    log.info('Media audio channel $channelId opened successfully.');
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

  Future<void> _handleStartIndication(ProtocolMessage message) async {
    AVChannelStartIndication startIndication =
        AVChannelStartIndication.fromBuffer(bodyOf(message));
    session = startIndication.session;
    currentStream = AudioService.CreateStream(
      startIndication.session,
      Channels.stereo,
      BufferType.s32le,
    );
    currentStream!.play();
  }

  Future<void> _handleStopIndication(ProtocolMessage message) async {
    AVChannelStopIndication stopIndication = AVChannelStopIndication.fromBuffer(
      bodyOf(message),
    );
    //TODO stop stream.
  }

  Future<void> _handleMediaWithTimeStampIndication(
    ProtocolMessage message,
  ) async {
    final Uint8List mediaData = bodyOf(message);
    if (currentStream != null) {
      currentStream!.appendData(mediaData);
      AVMediaAckIndication ackIndication = AVMediaAckIndication(
        sessionId: session,
        ackCount: 1,
      );
      await sendMessage(
        messageId: AVChannelMessage_Enum.AV_MEDIA_ACK_INDICATION.value,
        body: ackIndication.writeToBuffer(),
        encryptionType: EncryptionType.encrypted,
        messageType: MessageType.specific,
      );
      return;
    }
    log.warning(
      "Received TimeStamped Media Data while the session was closed!",
    );
  }
}
