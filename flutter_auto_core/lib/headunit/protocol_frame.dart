import 'dart:typed_data';

enum FrameType { middle, first, last, bulk }

enum MessageType { specific, control }

enum EncryptionType { plain, encrypted }

class ProtocolFrame {
  const ProtocolFrame({
    required this.channel,
    required this.frameType,
    required this.messageType,
    required this.encryptionType,
    required this.payload,
    this.totalMessageSize,
  });

  final int channel;
  final FrameType frameType;
  final MessageType messageType;
  final EncryptionType encryptionType;
  final Uint8List payload;
  final int? totalMessageSize;

  int get headerSize => frameType == FrameType.first ? 8 : 4;

  Uint8List encode() {
    _validate();

    final int flags =
        frameType.index |
        (messageType == MessageType.control ? 0x04 : 0) |
        (encryptionType == EncryptionType.encrypted ? 0x08 : 0);

    final Uint8List result = Uint8List(headerSize + payload.length);
    final ByteData data = ByteData.sublistView(result);

    result[0] = channel;
    result[1] = flags;
    data.setUint16(2, payload.length, Endian.big);

    if (frameType == FrameType.first) {
      data.setUint32(4, totalMessageSize!, Endian.big);
    }

    result.setRange(headerSize, result.length, payload);
    return result;
  }

  static ProtocolFrame decode(Uint8List bytes) {
    if (bytes.length < 4) {
      throw const FormatException('Frame header requires at least 4 bytes.');
    }

    final ByteData data = ByteData.sublistView(bytes);
    final int flags = bytes[1];
    final int rawFrameType = flags & 0x03;
    final int rawEncryptionType = (flags >> 3) & 0x01;
    final MessageType messageType = (flags & 0x04) != 0
        ? MessageType.control
        : MessageType.specific;
    if (rawFrameType >= FrameType.values.length) {
      throw FormatException('Invalid frame type: $rawFrameType.');
    }
    if (rawEncryptionType >= EncryptionType.values.length) {
      throw FormatException('Invalid encryption type: $rawEncryptionType.');
    }

    final FrameType frameType = FrameType.values[rawFrameType];
    final int headerSize = frameType == FrameType.first ? 8 : 4;

    if (bytes.length < headerSize) {
      throw const FormatException('Incomplete frame header.');
    }

    final int payloadLength = data.getUint16(2, Endian.big);
    final int? totalMessageSize = frameType == FrameType.first
        ? data.getUint32(4, Endian.big)
        : null;

    if (bytes.length != headerSize + payloadLength) {
      throw FormatException(
        'Frame length mismatch: expected ${headerSize + payloadLength} '
        'bytes, received ${bytes.length}.',
      );
    }

    final ProtocolFrame frame = ProtocolFrame(
      channel: bytes[0],
      frameType: frameType,
      messageType: messageType,
      encryptionType: EncryptionType.values[rawEncryptionType],
      payload: Uint8List.fromList(bytes.sublist(headerSize)),
      totalMessageSize: totalMessageSize,
    );

    frame._validate();
    return frame;
  }

  void _validate() {
    if (channel < 0 || channel > 0xFF) {
      throw ArgumentError.value(channel, 'channel', 'Must fit in one byte.');
    }

    if (payload.length > 0xFFFF) {
      throw ArgumentError.value(
        payload.length,
        'payload',
        'Frame payload cannot exceed 65535 bytes.',
      );
    }

    if (frameType == FrameType.first) {
      if (totalMessageSize == null ||
          totalMessageSize! <= payload.length ||
          totalMessageSize! > 0xFFFFFFFF) {
        throw ArgumentError(
          'FIRST frames require totalMessageSize greater than payload length.',
        );
      }
    } else if (totalMessageSize != null) {
      throw ArgumentError('Only FIRST frames may specify totalMessageSize.');
    }
  }
}
