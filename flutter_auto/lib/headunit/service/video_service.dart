
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_auto/generated/oaa/av/AVChannelData.pb.dart';
import 'package:flutter_auto/generated/oaa/av/AVChannelSetupRequestMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/av/AVChannelSetupResponseMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/av/AVChannelSetupStatusEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/av/AVChannelStartIndicationMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/av/AVMediaAckIndicationMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/av/MediaCodecTypeEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/common/StatusEnum.pbenum.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelDescriptorData.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelOpenRequestMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/control/ChannelOpenResponseMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/video/DisplayTypeEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/video/VideoConfigData.pb.dart';
import 'package:flutter_auto/generated/oaa/video/VideoFPSEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/video/VideoFocusIndicationMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/video/VideoFocusModeEnum.pb.dart';
import 'package:flutter_auto/generated/oaa/video/VideoFocusRequestMessage.pb.dart';
import 'package:flutter_auto/generated/oaa/video/VideoResolutionEnum.pb.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';
import 'package:flutter_auto/headunit/protocol_message.dart';
import 'package:flutter_auto/headunit/service/channel_service.dart';

/// Raw media received from the phone on the video channel.
///
/// `messageId` is either 0x0000 (timestamped media) or 0x0001
/// (media without a timestamp). [payload] retains the body as received;
/// timestamp parsing and decoding belong to the video pipeline.
class VideoMediaPacket {
  const VideoMediaPacket({
    required this.messageId,
    required this.payload,
  });

  final int messageId;
  final Uint8List payload;

  bool get hasTimestampHeader => messageId == 0x0000;
}

class VideoService extends ChannelService {
  static const String serviceName = 'video';
  static const int defaultChannelId = 3;

  static const int _channelOpenRequestId = 0x0007;
  static const int _channelOpenResponseId = 0x0008;

  static const int _setupRequestId = 0x8000;
  static const int _startIndicationId = 0x8001;
  static const int _stopIndicationId = 0x8002;
  static const int _setupResponseId = 0x8003;
  static const int _mediaAckId = 0x8004;

  static const int _videoFocusRequestId = 0x8007;
  static const int _videoFocusIndicationId = 0x8008;

  static const int _mediaWithTimestampId = 0x0000;
  static const int _mediaIndicationId = 0x0001;

  static const int _maxUnacked = 10;

  VideoService() : super(channelId: defaultChannelId);

  final StreamController<VideoMediaPacket> _videoPackets =
      StreamController<VideoMediaPacket>.broadcast();

  Stream<VideoMediaPacket> get videoPackets => _videoPackets.stream;

  bool _setupResponseSent = false;
  bool _isSetup = false;
  bool _isStreaming = false;

  int? _sessionId;
  int _ackCounter = 0;
  VideoFocusMode_Enum? _focusMode;

  bool get isSetup => _isSetup;
  bool get isStreaming => _isStreaming;
  int? get sessionId => _sessionId;
  VideoFocusMode_Enum? get focusMode => _focusMode;

  @override
  ChannelDescriptor buildDescriptor(int channelId) {
    return ChannelDescriptor()
      ..channelId = channelId
      ..avChannel = (AVChannel()
        ..streamType = MediaCodecType_Enum.MEDIA_CODEC_VIDEO_H264_BP
        ..displayId = 0
        ..displayType = DisplayType_Enum.MAIN
        ..videoConfigs.add(
          VideoConfig()
            ..codec = MediaCodecType_Enum.MEDIA_CODEC_VIDEO_H264_BP
            ..videoResolution = VideoResolution_Enum.VIDEO_800x480
            ..videoFps = VideoFPS_Enum.x30_
            ..marginWidth = 0
            ..marginHeight = 0
            ..dpi = 140,
        ));
  }

  @override
  Future<void> handleMessage(ProtocolMessage message) async {
    final int id = messageIdOf(message);

    if (id == _channelOpenRequestId) {
      await _handleChannelOpenRequest(message);
      return;
    }

    if (id == _setupRequestId) {
      await _handleSetupRequest(message);
      return;
    }

    if (id == _videoFocusRequestId) {
      await _handleVideoFocusRequest(message);
      return;
    }

    if (id == _startIndicationId) {
      _handleStartIndication(message);
      return;
    }

    if (id == _stopIndicationId) {
      _handleStopIndication();
      return;
    }

    if (id == _mediaWithTimestampId || id == _mediaIndicationId) {
      await _handleMediaPacket(message, id);
      return;
    }

    log.fine(
      'Unhandled video message: '
      '0x${id.toRadixString(16).padLeft(4, '0')}',
    );
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
      messageId: _channelOpenResponseId,
      body: response.writeToBuffer(),
      encryptionType: EncryptionType.encrypted,
      messageType: MessageType.control,
    );

    log.info('Video channel $channelId opened successfully.');
  }

  Future<void> _handleSetupRequest(ProtocolMessage message) async {
    if (_setupResponseSent) {
      // The reference warns that sending a second setup response on the
      // same video channel can cause the phone to terminate the session.
      log.warning('Ignoring duplicate video AV setup request.');
      return;
    }

    final request = AVChannelSetupRequest.fromBuffer(bodyOf(message));

    final bool codecSupported =
        request.mediaCodecType ==
        MediaCodecType_Enum.MEDIA_CODEC_VIDEO_H264_BP;

    log.info(
      'Video AV setup request: codec=${request.mediaCodecType}.',
    );

    // Current AVChannelSetupStatus schema: FAIL=1, OK=2.
    // Value 0 is not a valid success status.
    final response = AVChannelSetupResponse(
      mediaStatus: AVChannelSetupStatus_Enum.valueOf(
        codecSupported ? 2 : 1,
      )!,
      maxUnacked: codecSupported ? _maxUnacked : null,
      configs: codecSupported ? const [0] : const <int>[],
    );

    await sendMessage(
      messageId: _setupResponseId,
      body: response.writeToBuffer(),
      encryptionType: EncryptionType.encrypted,
      messageType: MessageType.specific,
    );

    _setupResponseSent = true;

    if (!codecSupported) {
      log.warning('Rejected unsupported video codec.');
      return;
    }

    _isSetup = true;
    log.info(
      'Video setup accepted: H.264, '
      '800x480, maxUnacked=$_maxUnacked.',
    );

    // Proactively grant projected focus after setup. Mark it unrequested
    // because this indication is not answering a focus request.
    final projectedMode = VideoFocusMode_Enum.valueOf(1)!;

    await _sendVideoFocusIndication(
      projectedMode,
      unrequested: true,
    );
  }

  Future<void> _handleVideoFocusRequest(ProtocolMessage message) async {
    final request = VideoFocusRequest.fromBuffer(bodyOf(message));
    final requestedMode = request.focusMode;

    _focusMode = requestedMode;

    log.info(
      'Video focus requested: mode=$requestedMode, '
      'reason=${request.focusReason}.',
    );

    await _sendVideoFocusIndication(
      requestedMode,
      unrequested: false,
    );
  }

  Future<void> _sendVideoFocusIndication(
    VideoFocusMode_Enum mode, {
    required bool unrequested,
  }) async {
    final indication = VideoFocusIndication(
      focusMode: mode,
      unrequested: unrequested,
    );

    await sendMessage(
      messageId: _videoFocusIndicationId,
      body: indication.writeToBuffer(),
      encryptionType: EncryptionType.encrypted,
      messageType: MessageType.specific,
    );

    _focusMode = mode;
    log.info(
      'Video focus set to $mode (unrequested=$unrequested).',
    );
  }

  void _handleStartIndication(ProtocolMessage message) {
    final start = AVChannelStartIndication.fromBuffer(bodyOf(message));

    _sessionId = start.session;
    _ackCounter = 0;
    _isStreaming = true;

    // Do not reject unfamiliar config indices. The phone's index is not
    // guaranteed to be a simple index into the advertised list.
    log.info(
      'Video stream started: session=${start.session}, '
      'config=${start.config}.',
    );
  }

  void _handleStopIndication() {
    _isStreaming = false;
    _sessionId = null;
    _ackCounter = 0;

    log.info('Video stream stopped.');
  }

  Future<void> _handleMediaPacket(
    ProtocolMessage message,
    int messageId,
  ) async {
    final payload = bodyOf(message);

    // Preserve the data exactly. SPS/PPS initialization data can arrive
    // without a presentation timestamp and must not be discarded.
    _videoPackets.add(
      VideoMediaPacket(
        messageId: messageId,
        payload: payload,
      ),
    );

    if (!_isStreaming || _sessionId == null) {
      log.fine(
        'Received video media before START_INDICATION: '
        '${payload.length} bytes.',
      );
      return;
    }

    // Keep the phone's flow-control window moving while the decoder
    // integration is being built. Once decoding is wired up, ACK after
    // the decoder has accepted each packet/frame instead.
    await _sendMediaAck();
  }

  Future<void> _sendMediaAck() async {
    final int? currentSession = _sessionId;
    if (currentSession == null) return;

    final ack = AVMediaAckIndication(
      sessionId: currentSession,
      ackCount: ++_ackCounter,
    );

    await sendMessage(
      messageId: _mediaAckId,
      body: ack.writeToBuffer(),
      encryptionType: EncryptionType.encrypted,
      messageType: MessageType.specific,
    );
  }

  @override
  Future<void> dispose() async {
    await _videoPackets.close();
    await super.dispose();
  }
}
