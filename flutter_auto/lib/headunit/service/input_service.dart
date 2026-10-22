import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/generated/oaa/input/InputChannelConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/input/TouchScreenConfigData.pb.dart';
import 'package:flutter_auto/headunit/protocol_message.dart';
import 'package:flutter_auto/headunit/service/channel_service.dart';

class InputService extends ChannelService{
  static const String serviceName = 'input';
  static const int defaultChannelId = 1;

  // Must match the video resolution advertised by VideoService.
  static const int videoWidth = 800;
  static const int videoHeight = 480;

  InputService() : super(channelId: defaultChannelId);

  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..inputChannel = (InputChannelConfig()
        ..displayId = 0
        ..supportedKeycodes.addAll([3, 4, 84])
        ..touchScreenConfigs.add(
          TouchScreenConfig(width: videoWidth, height: videoHeight),
        ));
  }

  Future<void> dispose() async {}
  @override
  Future<void> handleMessage(ProtocolMessage message) async {
    switch (messageIdOf(message)) {
      // Add the actual input message IDs from your generated protocol enums.
      default:
        log.fine('Unhandled input message');
    }
  }
}
