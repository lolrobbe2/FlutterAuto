/// Lightweight transport for compressed application media streams.
///
/// This package transports encoded access units. It does not capture Flutter
/// frames or encode/decode video; those operations belong to native platform
/// adapters (MediaCodec on Android and Media Foundation on Windows).
library;

export 'src/encoded_video_frame.dart';
export 'src/local_media_server.dart';
export 'src/media_stream_client.dart';
export 'src/media_stream_configuration.dart';
export 'src/media_stream_connection.dart';
export 'src/media_transport_exception.dart';
