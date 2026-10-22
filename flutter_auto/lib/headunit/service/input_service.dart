import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/generated/oaa/input/InputChannelConfigData.pb.dart';

class InputService {
  static const String serviceName = 'input';
  static const int defaultChannelId = 1;

  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..inputChannel = (InputChannelConfig()
        ..displayId = 0
        ..supportedKeycodes.addAll([3, 4, 84]));
  }

  Future<void> dispose() async {}
}
