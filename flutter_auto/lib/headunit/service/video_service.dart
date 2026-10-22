import 'package:flutter_auto/generated/oaa/av/AVChannelData.pb.dart';
import 'package:flutter_auto/generated/oaa/av/MediaCodecTypeEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/common/StatusEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelOpenRequestMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelOpenResponseMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ControlMessageIdsEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/video/DisplayTypeEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/video/VideoConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/video/VideoFPSEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/video/VideoResolutionEnum.pb.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';
import 'package:flutter_auto/headunit/protocol_message.dart';
import 'package:flutter_auto/headunit/service/channel_service.dart';

class VideoService extends ChannelService {
  static const String serviceName = 'video';
  static const int defaultChannelId = 3;

  VideoService() : super(channelId: defaultChannelId);

  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..avChannel = (AVChannel()
        ..streamType = MediaCodecType_Enum.MEDIA_CODEC_VIDEO_H264_BP
        ..displayId = 0
        ..displayType = DisplayType_Enum.MAIN
        ..videoConfigs.add(
          VideoConfig()
            ..codec = MediaCodecType_Enum.MEDIA_CODEC_VIDEO_H264_BP
            ..videoResolution = VideoResolution_Enum.VIDEO_800x480
            ..videoFps = VideoFPS_Enum.x30_
            ..marginWidth = 0
            ..marginHeight = 0
            ..dpi = 140,
        ));
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

    log.info('Video channel $channelId opened successfully.');
  }
}
