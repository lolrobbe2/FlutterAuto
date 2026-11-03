import 'package:flutter_auto_core/flutter_auto_core.dart';

class SensorService extends ChannelService {
  static const String serviceName = 'sensor';
  static const int defaultChannelId = 2;

  SensorService() : super(channelId: defaultChannelId);

  @override
  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..sensorChannel = (SensorChannel()
        ..sensors.addAll([
          SensorTypeEntry()..sensorType = SensorType_Enum.NIGHT_DATA,
          SensorTypeEntry()..sensorType = SensorType_Enum.DRIVING_STATUS,
          SensorTypeEntry()..sensorType = SensorType_Enum.PARKING_BRAKE,
        ]));
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

    if(id == SensorChannelMessage_Enum.SENSOR_REQUEST.value){
      await _handleSensorRequest(message);
      return;
    }

    log.warning(
      'Sensor Unhandled input message: '
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

  Future<void> _handleSensorRequest(ProtocolMessage message) async {
    SensorRequest request = SensorRequest.fromBuffer(bodyOf(message));
    
    SensorStartResponseMessage response = SensorStartResponseMessage(status: Status_Enum.OK);
    await sendMessage(
      messageId: SensorChannelMessage_Enum.SENSOR_START_RESPONSE.value,
      body: response.writeToBuffer(),
      encryptionType: EncryptionType.encrypted,
      messageType: MessageType.specific,
    );
  }
}
