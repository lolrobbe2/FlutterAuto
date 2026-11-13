import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'media_transport_exception.dart';

/// Small length-prefixed record channel over a single local TCP socket.
///
/// The reader consumes socket chunks incrementally and allocates at most one
/// bounded record at a time. Writes accept multiple parts to avoid copying a
/// multi-megabyte encoded frame into a second contiguous buffer.
class MediaSocketChannel {
  final Socket socket;
  final int maxRecordBytes;
  final int maxBufferedWriteBytes;
  final StreamIterator<Uint8List> _iterator;

  Uint8List? _currentChunk;
  int _currentOffset = 0;
  int _bufferedWriteBytes = 0;
  bool _closed = false;

  MediaSocketChannel(
    this.socket, {
    required this.maxRecordBytes,
    required this.maxBufferedWriteBytes,
  }) : _iterator = StreamIterator<Uint8List>(socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
  }

  bool get isClosed => _closed;

  Future<Uint8List?> readRecord({int? maximumBytes}) async {
    _ensureOpen();
    final Uint8List? rawHeader = await _readExactly(4, allowCleanEof: true);
    if (rawHeader == null) {
      return null;
    }
    final int length = ByteData.sublistView(rawHeader).getUint32(0, Endian.big);
    final int recordLimit = maximumBytes ?? maxRecordBytes;
    if (length == 0 || length > recordLimit || recordLimit > maxRecordBytes) {
      throw MediaTransportException('Invalid media record length: $length.');
    }
    final Uint8List? payload = await _readExactly(length);
    return payload!;
  }

  Future<Uint8List?> _readExactly(
    int length, {
    bool allowCleanEof = false,
  }) async {
    final Uint8List result = Uint8List(length);
    int written = 0;
    while (written < length) {
      Uint8List? chunk = _currentChunk;
      if (chunk == null || _currentOffset >= chunk.length) {
        final bool hasData = await _iterator.moveNext();
        if (!hasData) {
          if (allowCleanEof && written == 0) {
            return null;
          }
          throw const MediaTransportException(
            'Media socket closed mid-record.',
          );
        }
        chunk = _iterator.current;
        _currentChunk = chunk;
        _currentOffset = 0;
      }

      final int available = chunk.length - _currentOffset;
      final int count = available < length - written
          ? available
          : length - written;
      result.setRange(
        written,
        written + count,
        chunk,
        _currentOffset,
      );
      written += count;
      _currentOffset += count;
    }
    return result;
  }

  Future<void> writeRecord(
    List<Uint8List> parts, {
    required int payloadLength,
  }) async {
    _ensureOpen();
    if (payloadLength <= 0 || payloadLength > maxRecordBytes) {
      throw MediaTransportException('Invalid outgoing media record length.');
    }
    int actualPayloadLength = 0;
    for (final Uint8List part in parts) {
      actualPayloadLength += part.length;
    }
    if (actualPayloadLength != payloadLength) {
      throw ArgumentError.value(
        payloadLength,
        'payloadLength',
        'Does not match the supplied record parts.',
      );
    }
    final int recordLength = payloadLength + 4;
    if (_bufferedWriteBytes + recordLength > maxBufferedWriteBytes) {
      throw const MediaBackpressureException(
        'Encoded media send buffer is full; drop the stale frame.',
      );
    }

    final Uint8List header = Uint8List(4);
    ByteData.sublistView(header).setUint32(0, payloadLength, Endian.big);
    _bufferedWriteBytes += recordLength;
    try {
      socket.add(header);
      for (final Uint8List part in parts) {
        if (part.isNotEmpty) {
          socket.add(part);
        }
      }
      await socket.flush();
    } finally {
      _bufferedWriteBytes -= recordLength;
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    socket.destroy();
    await _iterator.cancel();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Media socket channel is closed.');
    }
  }
}
