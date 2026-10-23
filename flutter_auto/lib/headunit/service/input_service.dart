import 'dart:typed_data';

import 'package:flutter_auto/generated/oaa/common/StatusEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelOpenRequestMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelOpenResponseMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ControlMessageIdsEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/input/InputChannelConfigData.pb.dart';
import 'package:flutter_auto/headunit/input/input_base.dart';
import 'package:flutter_auto/headunit/input/touch_input.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';
import 'package:flutter_auto/headunit/protocol_message.dart';
import 'package:flutter_auto/headunit/service/channel_service.dart';

class InputService extends ChannelService {
  static const String serviceName = 'input';
  static const int defaultChannelId = 1;

  // Must match the video resolution advertised by VideoService.
  static const int videoWidth = 800;
  static const int videoHeight = 480;

  final List<InputBase> _inputs = [];

  /// Read-only view of registered input handlers.
  List<InputBase> get inputs => List.unmodifiable(_inputs);

  bool _inputServiceDisposed = false;

  InputService({
    Iterable<InputBase> inputs = const [],
  }) : super(channelId: defaultChannelId) {
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
      sendMessage: ({
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
          _inputs
              .whereType<TouchInput>()
              .map((input) => input.buildConfig()),
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

  Future<void> _handleChannelOpenRequest(
    ProtocolMessage message,
  ) async {
    final request = ChannelOpenRequest.fromBuffer(bodyOf(message));

    if (request.channelId != channelId) {
      log.warning(
        'Ignoring channel-open request for channel ${request.channelId}; '
        'this service owns channel $channelId.',
      );
      return;
    }

    final response = ChannelOpenResponse(
      status: Status_Enum.OK,
    );

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