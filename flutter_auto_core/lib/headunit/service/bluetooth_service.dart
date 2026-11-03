import 'package:flutter_auto_core/flutter_auto_core.dart';

/// Channel 5: navigation speech and assistant voice.
class BluetoothService extends ChannelService {
  static const String serviceName = 'bluetooth';
  static const int defaultChannelId = 8;

  BluetoothService() : super(channelId: defaultChannelId);

  @override
  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..bluetoothChannel = (BluetoothChannel()
        ..adapterAddress = "FlutterAuto"
        ..supportedPairingMethods.add(BluetoothPairingMethod_Enum.PIN));
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
    log.warning(
      'Bluetooth Unhandled input message: '
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

    log.info('Bluetooth channel $channelId opened successfully.');
  }
}
