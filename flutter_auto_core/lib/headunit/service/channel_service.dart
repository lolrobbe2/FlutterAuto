import 'dart:async';
import 'dart:typed_data';

import '../../generated/oaa/control/ChannelDescriptorData.pb.dart';
import '../protocol_message_sender.dart';
import 'package:logging/logging.dart';

import '../protocol_frame.dart';
import '../protocol_message.dart';

abstract class ChannelService {
  ChannelService({required this.channelId});

  final int channelId;
  final Logger log = Logger('ChannelService');

  ProtocolMessageSender? _sender;
  bool _disposed = false;

  final StreamController<ProtocolMessage> _incoming =
      StreamController<ProtocolMessage>.broadcast();

  Stream<ProtocolMessage> get messages => _incoming.stream;

  void attachSender(ProtocolMessageSender sender) {
    if (_disposed) {
      throw StateError('Cannot attach a disposed service.');
    }
    _sender = sender;
  }

  /// Return null for services not advertised in service discovery,
  /// such as the control service on channel 0.
  ChannelDescriptor? buildDescriptor(int channelId) => null;

  /// Called by ChannelServiceRegistry for messages on this service's channel.
  Future<void> handleMessage(ProtocolMessage message) async {
    log.fine(
      'Unhandled message on channel $channelId: '
      'id=0x${messageIdOf(message).toRadixString(16).padLeft(4, '0')}',
    );
  }

  Future<void> dispatch(ProtocolMessage message) async {
    if (_disposed) return;

    if (message.channel != channelId) {
      throw StateError(
        'Channel $channelId received message for channel ${message.channel}.',
      );
    }

    // Notify handshake transactions and any service-specific observers.
    _incoming.add(message);

    // The actual channel service owns message handling.
    await handleMessage(message);
  }

  Stream<ProtocolMessage> messagesForId(int messageId) {
    return messages.where((message) => messageIdOf(message) == messageId);
  }

  Future<ProtocolMessage> waitForMessage(
    int messageId, {
    Duration? timeout,
  }) {
    final future = messagesForId(messageId).first;
    return timeout == null ? future : future.timeout(timeout);
  }

  int messageIdOf(ProtocolMessage message) {
    if (message.payload.length < 2) {
      throw const FormatException('Message is missing its two-byte ID.');
    }

    return ByteData.sublistView(message.payload).getUint16(0, Endian.big);
  }

  Uint8List bodyOf(ProtocolMessage message) {
    if (message.payload.length < 2) {
      throw const FormatException('Message is missing its two-byte ID.');
    }

    return Uint8List.fromList(message.payload.sublist(2));
  }

  /// All service sends use this method, which fixes the service's channel ID.
  Future<void> sendMessage({
    required int messageId,
    required Uint8List body,
    required EncryptionType encryptionType,
    MessageType messageType = MessageType.specific,
    FrameType frameType = FrameType.bulk,
  }) {
    final sender = _sender;
    if (sender == null) {
      throw StateError('Service $channelId has not been registered.');
    }

    return sender.send(
      channelId: channelId,
      messageId: messageId,
      body: body,
      encryptionType: encryptionType,
      messageType: messageType,
      frameType: frameType,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _incoming.close();
  }
}