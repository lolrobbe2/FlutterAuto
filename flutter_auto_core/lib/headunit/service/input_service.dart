import 'dart:typed_data';

import 'package:flutter_auto_core/generated/oaa/video/VideoResolutionEnum.pbenum.dart';

import '../../generated/oaa/common/StatusEnum.pbenum.dart';
import '../../generated/oaa/control/ChannelDescriptorData.pb.dart';
import '../../generated/oaa/control/ChannelOpenRequestMessage.pb.dart';
import '../../generated/oaa/control/ChannelOpenResponseMessage.pb.dart';
import '../../generated/oaa/control/ControlMessageIdsEnum.pbenum.dart';
import '../../generated/oaa/input/InputChannelConfigData.pb.dart';
import '../input/input_base.dart';
import '../input/touch_input.dart';
import '../protocol_frame.dart';
import '../protocol_message.dart';
import 'channel_service.dart';

class InputService extends ChannelService {
  static const String serviceName = 'input';
  static const int defaultChannelId = 1;

  // Must match the video resolution advertised by VideoService.
  late int videoWidth;
  late int videoHeight;

  final List<InputBase> _inputs = [];

  /// Read-only view of registered input handlers.
  List<InputBase> get inputs => List.unmodifiable(_inputs);

  bool _inputServiceDisposed = false;

  InputService({
    Iterable<InputBase> inputs = const [],
    VideoResolution_Enum videoResolution = VideoResolution_Enum.VIDEO_800x480,
  }) : super(channelId: defaultChannelId) {
    switch (videoResolution) {
      case VideoResolution_Enum.VIDEO_800x480:
        videoWidth = 800;
        videoHeight = 480;
        break;

      case VideoResolution_Enum.VIDEO_1280x720:
        videoWidth = 1280;
        videoHeight = 720;
        break;

      case VideoResolution_Enum.VIDEO_1920x1080:
        videoWidth = 1920;
        videoHeight = 1080;
        break;

      case VideoResolution_Enum.VIDEO_2560x1440:
        videoWidth = 2560;
        videoHeight = 1440;
        break;

      case VideoResolution_Enum.VIDEO_3840x2160:
        videoWidth = 3840;
        videoHeight = 2160;
        break;

      case VideoResolution_Enum.VIDEO_720x1280:
        videoWidth = 720;
        videoHeight = 1280;
        break;

      case VideoResolution_Enum.VIDEO_1080x1920:
        videoWidth = 1080;
        videoHeight = 1920;
        break;

      case VideoResolution_Enum.VIDEO_1440x2560:
        videoWidth = 1440;
        videoHeight = 2560;
        break;

      case VideoResolution_Enum.VIDEO_2160x3840:
        videoWidth = 2160;
        videoHeight = 3840;
        break;

      default:
        //fallback to a sane default.
        videoWidth = 800;
        videoHeight = 480;
        break;
    }
    for (final input in inputs) {
      addInput(input);
    }
  }

  /// Registers an input handler and supplies the channel functions.
  ///
  /// Can be called during construction or any time afterward.
  void addInput(InputBase input) {
    if (_inputServiceDisposed) {
      throw StateError('Cannot add an input to a disposed InputService.');
    }

    if (_inputs.contains(input)) {
      throw StateError('This input is already registered.');
    }

    input.bindChannel(
      messageIdOf: messageIdOf,
      bodyOf: bodyOf,
      sendMessage:
          ({
            required int messageId,
            required Uint8List body,
            required EncryptionType encryptionType,
            required MessageType messageType,
            required FrameType frameType,
          }) {
            return sendMessage(
              messageId: messageId,
              body: body,
              encryptionType: encryptionType,
              messageType: messageType,
              frameType: frameType,
            );
          },
    );

    _inputs.add(input);

    log.info(
      'Registered input: ${input.runtimeType}. '
      'Total inputs=${_inputs.length}.',
    );
  }

  @override
  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..inputChannel = (InputChannelConfig()
        ..displayId = 0
        ..supportedKeycodes.addAll([3, 4, 84])
        ..touchScreenConfigs.addAll(
          _inputs.whereType<TouchInput>().map((input) => input.buildConfig()),
        ));
  }

  @override
  Future<void> handleMessage(ProtocolMessage message) async {
    final id = messageIdOf(message);

    if (id == ControlMessage_Enum.CHANNEL_OPEN_REQUEST.value) {
      await _handleChannelOpenRequest(message);
      return;
    }

    // Iterate over a snapshot in case inputs change during dispatch.
    for (final input in List<InputBase>.of(_inputs)) {
      await input.handleMessage(message);
    }
  }

  Future<void> _handleChannelOpenRequest(ProtocolMessage message) async {
    final request = ChannelOpenRequest.fromBuffer(bodyOf(message));

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

    log.info('Input channel $channelId opened successfully.');
  }

  @override
  Future<void> dispose() async {
    if (_inputServiceDisposed) return;

    _inputServiceDisposed = true;

    for (final input in List<InputBase>.of(_inputs)) {
      await input.dispose();
    }

    _inputs.clear();

    await super.dispose();
  }
}
