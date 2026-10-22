import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/generated/oaa/sensor/SensorChannelConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/sensor/SensorChannelData.pb.dart';
import 'package:flutter_auto/generated/oaa/sensor/SensorTypeEnum.pbenum.dart';

class SensorService {
  static const String serviceName = 'sensor';
  static const int defaultChannelId = 2;

  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..sensorChannel = (SensorChannel()
        ..sensors.addAll([
          SensorTypeEntry()
            ..sensorType = SensorType_Enum.NIGHT_DATA,
          SensorTypeEntry()
            ..sensorType = SensorType_Enum.DRIVING_STATUS,
        ]));
  }

  Future<void> dispose() async {}
}
