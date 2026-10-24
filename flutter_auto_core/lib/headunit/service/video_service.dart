import 'dart:async';
import 'dart:typed_data';

import '../../generated/oaa/av/AVChannelData.pb.dart';
import '../../generated/oaa/av/AVChannelSetupRequestMessage.pb.dart';
import '../../generated/oaa/av/AVChannelSetupResponseMessage.pb.dart';
import '../../generated/oaa/av/AVChannelSetupStatusEnum.pb.dart';
import '../../generated/oaa/av/AVChannelStartIndicationMessage.pb.dart';
import '../../generated/oaa/av/AVMediaAckIndicationMessage.pb.dart';
import '../../generated/oaa/av/MediaCodecTypeEnum.pb.dart';
import '../../generated/oaa/common/StatusEnum.pbenum.dart';
import '../../generated/oaa/control/ChannelDescriptorData.pb.dart';
import '../../generated/oaa/control/ChannelOpenRequestMessage.pb.dart';
import '../../generated/oaa/control/ChannelOpenResponseMessage.pb.dart';
import '../../generated/oaa/control/ControlMessageIdsEnum.pbenum.dart';
import '../../generated/oaa/video/DisplayTypeEnum.pb.dart';
import '../../generated/oaa/video/VideoConfigData.pb.dart';
import '../../generated/oaa/video/VideoFPSEnum.pb.dart';
import '../../generated/oaa/video/VideoFocusIndicationMessage.pb.dart';
import '../../generated/oaa/video/VideoFocusModeEnum.pb.dart';
import '../../generated/oaa/video/VideoFocusRequestMessage.pb.dart';
import '../../generated/oaa/video/VideoResolutionEnum.pb.dart';
import '../protocol_frame.dart';
import '../protocol_message.dart';
import 'channel_service.dart';
import '../video/video_message_id.dart';

/// Raw media received from the phone on the video channel.
///
/// `messageId` is either 0x0000 (timestamped media) or 0x0001
/// (media without a timestamp). [payload] retains the body as received;
/// timestamp parsing and decoding belong to the video pipeline.
class VideoMediaPacket {
  const VideoMediaPacket({required this.messageId, required this.payload});

  final int messageId;
  final Uint8List payload;

  bool get hasTimestampHeader => messageId == 0x0000;
}

class VideoService extends ChannelService {
  static const String serviceName = 'video';
  static const int defaultChannelId = 3;

  static const int _maxUnacked = 10;

  VideoService({
    this.resolution = VideoResolution_Enum.VIDEO_800x480,
    this.fps = VideoFPS_Enum.x30_,
    this.dpi = 140,
  }) : super(channelId: defaultChannelId);

  /// Video resolution advertised to the Android phone.
  final VideoResolution_Enum resolution;

  /// Requested video frame rate.
  final VideoFPS_Enum fps;

  /// Display density advertised to the phone.
  final int dpi;
  final StreamController<VideoMediaPacket> _videoPackets =
      StreamController<VideoMediaPacket>.broadcast();

  Stream<VideoMediaPacket> get videoPackets => _videoPackets.stream;

  bool _setupResponseSent = false;
  bool _isSetup = false;
  bool _isStreaming = false;

  int? _sessionId;
  int _ackCounter = 0;
  VideoFocusMode_Enum? _focusMode;
  int _receivedVideoPackets = 0;
  bool get isSetup => _isSetup;
  bool get isStreaming => _isStreaming;
  int? get sessionId => _sessionId;
  VideoFocusMode_Enum? get focusMode => _focusMode;
  VideoMediaPacket? _codecConfigPacket;

  VideoMediaPacket? get codecConfigPacket {
    final packet = _codecConfigPacket;
    if (packet == null) return null;

    return VideoMediaPacket(
      messageId: packet.messageId,
      payload: Uint8List.fromList(packet.payload),
    );
  }

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
            ..videoResolution = resolution
            ..videoFps = fps
            ..marginWidth = 0
            ..marginHeight = 0
            ..dpi = dpi,
        ));
  }

  @override
  Future<void> handleMessage(ProtocolMessage message) async {
    final int rawId = messageIdOf(message);
    final VideoMessageId? id = VideoMessageId.fromValue(rawId);

    if (id == null) {
      log.warning(
        'Unknown video message ID: '
        '0x${rawId.toRadixString(16).padLeft(4, '0')}.',
      );
      return;
    }

    switch (id) {
      case VideoMessageId.channelOpenRequest:
        await _handleChannelOpenRequest(message);
      case VideoMessageId.avChannelSetupRequest:
        await _handleSetupRequest(message);
      case VideoMessageId.videoFocusRequest:
        await _handleVideoFocusRequest(message);
      case VideoMessageId.avChannelStartIndication:
        _handleStartIndication(message);
      case VideoMessageId.avChannelStopIndication:
        _handleStopIndication();
      case VideoMessageId.mediaWithTimestamp:
      case VideoMessageId.media:
        await _handleMediaPacket(message, id);
      case VideoMessageId.channelOpenResponse:
      case VideoMessageId.avChannelSetupResponse:
      case VideoMessageId.avMediaAckIndication:
      case VideoMessageId.videoFocusIndication:
        log.fine('Received response/indication: $id.');
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
        request.mediaCodecType == MediaCodecType_Enum.MEDIA_CODEC_VIDEO_H264_BP;

    log.info('Video AV setup request: codec=${request.mediaCodecType}.');

    // Current AVChannelSetupStatus schema: FAIL=1, OK=2.
    // Value 0 is not a valid success status.
    final response = AVChannelSetupResponse(
      mediaStatus: AVChannelSetupStatus_Enum.valueOf(codecSupported ? 2 : 1)!,
      maxUnacked: codecSupported ? _maxUnacked : null,
      configs: codecSupported ? const [0] : const <int>[],
    );

    await sendMessage(
      messageId: VideoMessageId.avChannelSetupResponse.value,
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
      '$resolution, maxUnacked=$_maxUnacked.',
    );

    // Proactively grant projected focus after setup. Mark it unrequested
    // because this indication is not answering a focus request.
    final projectedMode = VideoFocusMode_Enum.valueOf(1)!;

    await _sendVideoFocusIndication(projectedMode, unrequested: true);
  }

  Future<void> _handleVideoFocusRequest(ProtocolMessage message) async {
    final request = VideoFocusRequest.fromBuffer(bodyOf(message));
    final requestedMode = request.focusMode;

    _focusMode = requestedMode;

    log.info(
      'Video focus requested: mode=$requestedMode, '
      'reason=${request.focusReason}.',
    );

    await _sendVideoFocusIndication(requestedMode, unrequested: false);
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
      messageId: VideoMessageId.videoFocusIndication.value,
      body: indication.writeToBuffer(),
      encryptionType: EncryptionType.encrypted,
      messageType: MessageType.specific,
    );

    _focusMode = mode;
    log.info('Video focus set to $mode (unrequested=$unrequested).');
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
    VideoMessageId messageId,
  ) async {
    final payload = bodyOf(message);
    final count = ++_receivedVideoPackets;

    if (count <= 5 || count % 60 == 0) {
      log.fine(
        'RX VIDEO #$count: '
        'id=0x${messageId.value.toRadixString(16).padLeft(4, '0')}, '
        'bytes=${payload.length}, '
        'streaming=$_isStreaming, '
        'session=$_sessionId',
      );
    }

    if (messageId == VideoMessageId.media) {
      _codecConfigPacket = VideoMediaPacket(
        messageId: messageId.value,
        payload: Uint8List.fromList(payload),
      );
    }

    _videoPackets.add(
      VideoMediaPacket(
        messageId: messageId.value,
        payload: Uint8List.fromList(payload),
      ),
    );

    if (!_isStreaming || _sessionId == null) {
      log.finer('Received video media before START_INDICATION.');
      return;
    }

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
      messageId: VideoMessageId.avMediaAckIndication.value,
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
