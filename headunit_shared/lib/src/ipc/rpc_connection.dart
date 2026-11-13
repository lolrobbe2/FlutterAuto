import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'rpc_exception.dart';
import 'rpc_notification.dart';

typedef RpcRequestHandler = FutureOr<Object?> Function(
  Map<String, Object?> parameters,
);

/// Multiplexes small control/service messages over one TCP socket.
///
/// Wire format:
///   uint32 big-endian payload length
///   UTF-8 JSON object
///
/// Video and other high-volume binary data must use a separate media channel.
class RpcConnection {
  static const int protocolVersion = 1;
  static const int defaultMaxFrameBytes = 64 * 1024;
  static const int maxPendingRequests = 64;
  static const int maxConcurrentHandlers = 32;

  final Socket _socket;
  final int _maxFrameBytes;
  final Map<int, Completer<Object?>> _pendingRequests = {};
  final Map<String, RpcRequestHandler> _requestHandlers = {};
  final StreamController<RpcNotification> _notifications =
      StreamController<RpcNotification>.broadcast(sync: true);
  final Completer<void> _done = Completer<void>();

  late final StreamSubscription<Uint8List> _socketSubscription;
  Uint8List _input = Uint8List(0);
  int _inputOffset = 0;
  int _nextRequestId = 1;
  int _activeHandlers = 0;
  bool _closed = false;

  RpcConnection._(this._socket, {required int maxFrameBytes})
    : _maxFrameBytes = maxFrameBytes {
    _socket.setOption(SocketOption.tcpNoDelay, true);
    _socketSubscription = _socket.listen(
      _onData,
      onError: (Object error, StackTrace stackTrace) {
        _terminate(RpcException(-32098, 'Socket failed: $error'));
      },
      onDone: () {
        _terminate(const RpcException(-32098, 'RPC connection closed.'));
      },
      cancelOnError: true,
    );
  }

  factory RpcConnection.fromSocket(
    Socket socket, {
    int maxFrameBytes = defaultMaxFrameBytes,
  }) {
    if (maxFrameBytes <= 0) {
      throw ArgumentError.value(maxFrameBytes, 'maxFrameBytes');
    }
    return RpcConnection._(socket, maxFrameBytes: maxFrameBytes);
  }

  static Future<RpcConnection> connect({
    required String host,
    required int port,
    Duration timeout = const Duration(seconds: 10),
    int maxFrameBytes = defaultMaxFrameBytes,
  }) async {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port');
    }
    if (maxFrameBytes <= 0) {
      throw ArgumentError.value(maxFrameBytes, 'maxFrameBytes');
    }

    final Socket socket = await Socket.connect(host, port, timeout: timeout);
    return RpcConnection._(socket, maxFrameBytes: maxFrameBytes);
  }

  bool get isClosed => _closed;

  Future<void> get done => _done.future;

  Stream<RpcNotification> get notifications => _notifications.stream;

  void registerRequestHandler(String method, RpcRequestHandler handler) {
    _ensureOpen();
    if (method.trim().isEmpty) {
      throw ArgumentError.value(method, 'method');
    }
    if (_requestHandlers.containsKey(method)) {
      throw StateError('An RPC handler for "$method" is already registered.');
    }
    _requestHandlers[method] = handler;
  }

  bool unregisterRequestHandler(String method) {
    _ensureOpen();
    return _requestHandlers.remove(method) != null;
  }

  Future<Object?> request(
    String method, {
    Map<String, Object?> parameters = const <String, Object?>{},
    Duration timeout = const Duration(seconds: 10),
  }) {
    _ensureOpen();
    if (method.trim().isEmpty) {
      throw ArgumentError.value(method, 'method');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    if (_pendingRequests.length >= maxPendingRequests) {
      throw StateError('Too many outstanding RPC requests.');
    }

    if (_nextRequestId > 0x7fffffff) {
      if (_pendingRequests.isNotEmpty) {
        throw StateError('RPC request ID space exhausted.');
      }
      _nextRequestId = 1;
    }

    final int requestId = _nextRequestId++;
    final Completer<Object?> completer = Completer<Object?>();
    _pendingRequests[requestId] = completer;

    try {
      _send(<String, Object?>{
        'v': protocolVersion,
        't': 'req',
        'id': requestId,
        'm': method,
        'p': parameters,
      });
    } catch (error, stackTrace) {
      _pendingRequests.remove(requestId);
      completer.completeError(error, stackTrace);
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(requestId);
        throw RpcException(-32097, 'RPC request timed out: $method');
      },
    );
  }

  void notify(
    String method, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) {
    _ensureOpen();
    if (method.trim().isEmpty) {
      throw ArgumentError.value(method, 'method');
    }

    _send(<String, Object?>{
      'v': protocolVersion,
      't': 'evt',
      'm': method,
      'p': parameters,
    });
  }

  void _onData(Uint8List chunk) {
    if (_closed || chunk.isEmpty) {
      return;
    }

    try {
      final int unreadBytes = _input.length - _inputOffset;
      final Uint8List combined = Uint8List(unreadBytes + chunk.length);
      if (unreadBytes > 0) {
        combined.setRange(0, unreadBytes, _input, _inputOffset);
      }
      combined.setRange(unreadBytes, combined.length, chunk);
      _input = combined;
      _inputOffset = 0;

      while (!_closed) {
        final int available = _input.length - _inputOffset;
        if (available < 4) {
          break;
        }

        final ByteData header = ByteData.sublistView(
          _input,
          _inputOffset,
          _inputOffset + 4,
        );
        final int payloadLength = header.getUint32(0, Endian.big);

        if (payloadLength == 0 || payloadLength > _maxFrameBytes) {
          throw FormatException(
            'Invalid RPC frame length: $payloadLength bytes.',
          );
        }
        if (available < payloadLength + 4) {
          break;
        }

        final Uint8List payload = Uint8List.sublistView(
          _input,
          _inputOffset + 4,
          _inputOffset + 4 + payloadLength,
        );
        _inputOffset += payloadLength + 4;
        _handleFrame(payload);
      }

      final int remaining = _input.length - _inputOffset;
      if (remaining == 0) {
        _input = Uint8List(0);
        _inputOffset = 0;
      } else if (_inputOffset > 0) {
        final Uint8List compacted = Uint8List(remaining);
        compacted.setRange(0, remaining, _input, _inputOffset);
        _input = compacted;
        _inputOffset = 0;
      }
    } catch (error) {
      _terminate(RpcException(-32700, 'Invalid RPC frame: $error'));
    }
  }

  void _handleFrame(Uint8List payload) {
    final Object? decoded = jsonDecode(utf8.decode(payload));
    final Map<String, Object?> message = _toStringMap(decoded);

    if (message['v'] != protocolVersion) {
      throw FormatException(
        'Unsupported RPC protocol version: ${message['v']}',
      );
    }

    switch (message['t']) {
      case 'req':
        final int id = _readInt(message, 'id');
        if (id <= 0) {
          throw const FormatException('RPC request ID must be positive.');
        }
        final String method = _readString(message, 'm');
        final Map<String, Object?> parameters = _readMap(message, 'p');
        if (_activeHandlers >= maxConcurrentHandlers) {
          _sendResponseError(
            id,
            const RpcException(-32096, 'RPC server is busy.'),
          );
          return;
        }
        _activeHandlers++;
        unawaited(
          _handleRequest(id, method, parameters)
              .whenComplete(() {
                _activeHandlers--;
              })
              .catchError((Object error, StackTrace stackTrace) {
                _terminate(error);
              }),
        );
        return;
      case 'res':
        _handleResponse(message);
        return;
      case 'evt':
        final String method = _readString(message, 'm');
        final Map<String, Object?> parameters = _readMap(message, 'p');
        _notifications.add(
          RpcNotification(method: method, parameters: parameters),
        );
        return;
      default:
        throw FormatException('Unknown RPC message type: ${message['t']}');
    }
  }

  Future<void> _handleRequest(
    int requestId,
    String method,
    Map<String, Object?> parameters,
  ) async {
    final RpcRequestHandler? handler = _requestHandlers[method];
    if (handler == null) {
      _sendResponseError(
        requestId,
        const RpcException(-32601, 'Method not found.'),
      );
      return;
    }

    try {
      final Object? result = await handler(parameters);
      _send(<String, Object?>{
        'v': protocolVersion,
        't': 'res',
        'id': requestId,
        'r': result,
      });
    } catch (error) {
      final RpcException rpcError = error is RpcException
          ? error
          : RpcException(-32000, error.toString());
      _sendResponseError(requestId, rpcError);
    }
  }

  void _sendResponseError(int requestId, RpcException error) {
    if (_closed) {
      return;
    }
    _send(<String, Object?>{
      'v': protocolVersion,
      't': 'res',
      'id': requestId,
      'e': <String, Object?>{
        'c': error.code,
        'm': error.message,
        'd': error.data,
      },
    });
  }

  void _handleResponse(Map<String, Object?> message) {
    final int requestId = _readInt(message, 'id');
    if (requestId <= 0) {
      throw const FormatException('RPC response ID must be positive.');
    }
    final Completer<Object?>? completer = _pendingRequests.remove(requestId);
    if (completer == null || completer.isCompleted) {
      return;
    }

    final Object? rawError = message['e'];
    if (rawError != null) {
      final Map<String, Object?> error = _toStringMap(rawError);
      final int code = _readInt(error, 'c');
      final String text = _readString(error, 'm');
      completer.completeError(RpcException(code, text, data: error['d']));
      return;
    }

    completer.complete(message['r']);
  }

  void _send(Map<String, Object?> message) {
    _ensureOpen();
    final List<int> encoded = utf8.encode(jsonEncode(message));
    if (encoded.isEmpty || encoded.length > _maxFrameBytes) {
      throw RpcException(
        -32095,
        'RPC message exceeds the $_maxFrameBytes byte frame limit.',
      );
    }

    final Uint8List frame = Uint8List(encoded.length + 4);
    ByteData.sublistView(frame, 0, 4).setUint32(0, encoded.length, Endian.big);
    frame.setRange(4, frame.length, encoded);
    _socket.add(frame);
  }

  void _terminate(Object reason) {
    if (_closed) {
      return;
    }
    _closed = true;
    _socket.destroy();

    for (final Completer<Object?> completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(reason);
      }
    }
    _pendingRequests.clear();
    _requestHandlers.clear();

    if (!_notifications.isClosed) {
      unawaited(_notifications.close());
    }
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  Future<void> close() async {
    if (!_closed) {
      _terminate(const RpcException(-32098, 'RPC connection closed locally.'));
    }
    await _socketSubscription.cancel();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('RPC connection is closed.');
    }
  }

  static int _readInt(Map<String, Object?> map, String key) {
    final Object? value = map[key];
    if (value is! int) {
      throw FormatException('RPC field "$key" must be an integer.');
    }
    return value;
  }

  static String _readString(Map<String, Object?> map, String key) {
    final Object? value = map[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('RPC field "$key" must be a non-empty string.');
    }
    return value;
  }

  static Map<String, Object?> _readMap(Map<String, Object?> map, String key) {
    return _toStringMap(map[key]);
  }

  static Map<String, Object?> _toStringMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Expected a JSON object.');
    }

    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('JSON object keys must be strings.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
}
