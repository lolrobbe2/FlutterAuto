import 'package:flutter_auto_core/flutter_auto_core.dart';

/// Channel 5: navigation speech and assistant voice.
class NavigationService extends ChannelService {
  static const String serviceName = 'navigation';
  static const int defaultChannelId = 9;

  NavigationService() : super(channelId: defaultChannelId);

  @override
  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..navigationChannel = NavigationChannel(
        minimumIntervalMs: 500,
        type: NavigationType_Enum.TURN_BY_TURN,
        imageOptions: NavigationImageOptions(
          height: 64,
          width: 64,
          colourDepthBits: 32,
        ),
      );
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
      'Navigation Unhandled input message: '
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

    log.info('Navigation channel $channelId opened successfully.');
  }
}
