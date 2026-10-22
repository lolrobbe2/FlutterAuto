import 'package:flutter_auto/generated/oaa/common/StatusEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelOpenRequestMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelOpenResponseMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ControlMessageIdsEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/sensor/SensorChannelConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/sensor/SensorChannelData.pb.dart';
import 'package:flutter_auto/generated/oaa/sensor/SensorTypeEnum.pbenum.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';
import 'package:flutter_auto/headunit/protocol_message.dart';
import 'package:flutter_auto/headunit/service/channel_service.dart';

class SensorService extends ChannelService {
  static const String serviceName = 'sensor';
  static const int defaultChannelId = 2;

  SensorService() : super(channelId: defaultChannelId);

  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..sensorChannel = (SensorChannel()
        ..sensors.addAll([
          SensorTypeEntry()..sensorType = SensorType_Enum.NIGHT_DATA,
          SensorTypeEntry()..sensorType = SensorType_Enum.DRIVING_STATUS,
        ]));
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

    log.info('Sensor channel $channelId opened successfully.');
  }
}
