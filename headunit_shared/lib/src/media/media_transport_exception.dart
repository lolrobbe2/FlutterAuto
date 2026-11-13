/// Error raised by the local compressed-media transport.
class MediaTransportException implements Exception {
  final String message;
  const MediaTransportException(this.message);

  @override
  String toString() => 'MediaTransportException: $message';
}

/// A sender attempted to queue more encoded data than the transport allows.
class MediaBackpressureException extends MediaTransportException {
  const MediaBackpressureException(super.message);
}
