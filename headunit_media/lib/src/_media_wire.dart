import 'dart:convert';
import 'dart:typed_data';

import 'encoded_video_frame.dart';
import 'media_stream_configuration.dart';
import 'media_transport_exception.dart';

const int _helloRecord = 0x01;
const int _configurationRecord = 0x02;
const int _requestKeyFrameRecord = 0x03;
const int _videoFrameRecord = 0x10;
const int videoFrameHeaderBytes = 18;

Uint8List encodeHello(String token) {
  final List<int> tokenBytes = utf8.encode(token);
  if (tokenBytes.length < 16 || tokenBytes.length > 512) {
    throw ArgumentError.value(
      token,
      'token',
      'Token must be 16..512 UTF-8 bytes.',
    );
  }
  final Uint8List result = Uint8List(4 + tokenBytes.length);
  result[0] = _helloRecord;
  result[1] = 1; // Media protocol version.
  ByteData.sublistView(result).setUint16(2, tokenBytes.length, Endian.big);
  result.setRange(4, result.length, tokenBytes);
  return result;
}

String decodeHello(Uint8List record) {
  if (record.length < 4 || record[0] != _helloRecord || record[1] != 1) {
    throw const MediaTransportException('Invalid media handshake or version.');
  }
  final int length = ByteData.sublistView(record).getUint16(2, Endian.big);
  if (length < 16 || length > 512 || record.length != 4 + length) {
    throw const MediaTransportException('Invalid media authentication token.');
  }
  try {
    return utf8.decode(record.sublist(4), allowMalformed: false);
  } on FormatException {
    throw const MediaTransportException('Media token is not valid UTF-8.');
  }
}

Uint8List encodeConfiguration(VideoStreamConfiguration configuration) {
  configuration.validate();
  final Uint8List result = Uint8List(14);
  result[0] = _configurationRecord;
  result[1] = 1; // Media protocol version.
  result[2] = configuration.codec.wireValue;
  final ByteData data = ByteData.sublistView(result);
  data.setUint16(3, configuration.width, Endian.big);
  data.setUint16(5, configuration.height, Endian.big);
  data.setUint16(7, configuration.framesPerSecond, Endian.big);
  data.setUint32(9, configuration.targetBitrateBitsPerSecond, Endian.big);
  result[13] = configuration.rotationDegrees ~/ 90;
  return result;
}

VideoStreamConfiguration decodeConfiguration(Uint8List record) {
  if (record.length != 14 ||
      record[0] != _configurationRecord ||
      record[1] != 1) {
    throw const MediaTransportException('Invalid video configuration record.');
  }
  final ByteData data = ByteData.sublistView(record);
  final int rotationCode = record[13];
  if (rotationCode > 3) {
    throw const MediaTransportException('Invalid video rotation.');
  }
  final VideoStreamConfiguration configuration = VideoStreamConfiguration(
    codec: VideoCodec.fromWireValue(record[2]),
    width: data.getUint16(3, Endian.big),
    height: data.getUint16(5, Endian.big),
    framesPerSecond: data.getUint16(7, Endian.big),
    targetBitrateBitsPerSecond: data.getUint32(9, Endian.big),
    rotationDegrees: rotationCode * 90,
  );
  try {
    configuration.validate();
  } on ArgumentError catch (error) {
    throw MediaTransportException('Invalid video configuration: $error');
  }
  return configuration;
}

Uint8List encodeVideoFrameHeader(EncodedVideoFrame frame) {
  final Uint8List result = Uint8List(videoFrameHeaderBytes);
  result[0] = _videoFrameRecord;
  final ByteData data = ByteData.sublistView(result);
  data.setUint64(1, frame.sequenceNumber, Endian.big);
  data.setUint64(9, frame.presentationTimeMicros, Endian.big);
  result[17] = frame.isKeyFrame ? 1 : 0;
  return result;
}

EncodedVideoFrame decodeVideoFrame(Uint8List record) {
  if (record.length <= videoFrameHeaderBytes ||
      record[0] != _videoFrameRecord) {
    throw const MediaTransportException('Invalid encoded video frame.');
  }
  final ByteData data = ByteData.sublistView(record);
  final int flags = record[17];
  if ((flags & 0xfe) != 0) {
    throw const MediaTransportException('Unknown encoded video frame flags.');
  }
  return EncodedVideoFrame(
    sequenceNumber: data.getUint64(1, Endian.big),
    presentationTimeMicros: data.getUint64(9, Endian.big),
    isKeyFrame: (flags & 0x01) != 0,
    // A view avoids copying the access unit after reading the bounded record.
    data: Uint8List.sublistView(record, videoFrameHeaderBytes),
  );
}

Uint8List get requestKeyFrameRecord =>
    Uint8List.fromList(<int>[_requestKeyFrameRecord]);

bool isRequestKeyFrameRecord(Uint8List record) =>
    record.length == 1 && record[0] == _requestKeyFrameRecord;

bool constantTimeTokenEquals(String supplied, String expected) {
  final List<int> left = utf8.encode(supplied);
  final List<int> right = utf8.encode(expected);
  if (left.length != right.length) {
    return false;
  }
  int difference = 0;
  for (int index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
