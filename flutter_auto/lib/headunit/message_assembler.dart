import 'dart:async';
import 'dart:typed_data';

import 'protocol_frame.dart';
import 'protocol_message.dart';

class MessageAssembler {
  const MessageAssembler();

  Stream<ProtocolMessage> bind(Stream<ProtocolFrame> frames) async* {
    final Map<int, _PendingMessage> pendingMessages = <int, _PendingMessage>{};

    await for (final ProtocolFrame frame in frames) {
      final int channel = frame.channel;

      switch (frame.frameType) {
        case FrameType.bulk:
          if (pendingMessages.containsKey(channel)) {
            throw FormatException(
              'Received BULK frame on channel $channel '
              'while a fragmented message is incomplete.',
            );
          }

          yield ProtocolMessage(
            channel: channel,
            messageType: frame.messageType,
            encryptionType: frame.encryptionType,
            payload: Uint8List.fromList(frame.payload),
          );
          break;

        case FrameType.first:
          if (pendingMessages.containsKey(channel)) {
            throw FormatException(
              'Received FIRST frame on channel $channel '
              'while another message is incomplete.',
            );
          }

          final int? totalMessageSize = frame.totalMessageSize;

          if (totalMessageSize == null) {
            throw FormatException(
              'FIRST frame on channel $channel has no total message size.',
            );
          }

          if (frame.payload.length > totalMessageSize) {
            throw FormatException(
              'FIRST frame payload exceeds the declared message size '
              'on channel $channel.',
            );
          }

          pendingMessages[channel] = _PendingMessage(
            messageType: frame.messageType,
            encryptionType: frame.encryptionType,
            totalMessageSize: totalMessageSize,
            payload: BytesBuilder(copy: false)..add(frame.payload),
          );
          break;

        case FrameType.middle:
          final _PendingMessage? pending = pendingMessages[channel];

          if (pending == null) {
            throw FormatException(
              'Received MIDDLE frame on channel $channel '
              'without a preceding FIRST frame.',
            );
          }

          _validateMetadata(frame, pending);

          final int newSize = pending.payload.length + frame.payload.length;

          if (newSize > pending.totalMessageSize) {
            throw FormatException(
              'Fragmented message on channel $channel exceeds '
              'its declared size.',
            );
          }

          pending.payload.add(frame.payload);
          break;

        case FrameType.last:
          final _PendingMessage? pending = pendingMessages[channel];

          if (pending == null) {
            throw FormatException(
              'Received LAST frame on channel $channel '
              'without a preceding FIRST frame.',
            );
          }

          _validateMetadata(frame, pending);

          final int newSize = pending.payload.length + frame.payload.length;

          if (newSize != pending.totalMessageSize) {
            throw FormatException(
              'Fragmented message on channel $channel has size $newSize, '
              'expected ${pending.totalMessageSize}.',
            );
          }

          pending.payload.add(frame.payload);
          pendingMessages.remove(channel);

          yield ProtocolMessage(
            channel: channel,
            messageType: pending.messageType,
            encryptionType: pending.encryptionType,
            payload: pending.payload.takeBytes(),
          );
      }
    }

    if (pendingMessages.isNotEmpty) {
      throw FormatException(
        'Frame stream ended with incomplete messages on channels: '
        '${pendingMessages.keys.join(', ')}.',
      );
    }
  }

  void _validateMetadata(ProtocolFrame frame, _PendingMessage pending) {
    if (frame.messageType != pending.messageType) {
      throw FormatException(
        'Message type changed during fragmentation on channel '
        '${frame.channel}.',
      );
    }

    if (frame.encryptionType != pending.encryptionType) {
      throw FormatException(
        'Encryption type changed during fragmentation on channel '
        '${frame.channel}.',
      );
    }
  }
}

class _PendingMessage {
  _PendingMessage({
    required this.messageType,
    required this.encryptionType,
    required this.totalMessageSize,
    required this.payload,
  });

  final MessageType messageType;
  final EncryptionType encryptionType;
  final int totalMessageSize;
  final BytesBuilder payload;
}
