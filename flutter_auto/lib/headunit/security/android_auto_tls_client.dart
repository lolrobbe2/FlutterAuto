import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';
import 'package:openssl_bindings/openssl.dart' as openssl;

import 'head_unit_identity.dart';
import 'ssl_handshake_transport.dart';

/// Performs an in-memory TLS 1.2 client handshake over Android Auto's
/// SSL_HANDSHAKE protocol messages.
///
/// The SSL object owns its read and write BIOs after SSL_set_bio succeeds.
class AndroidAutoTlsClient {
  static final Logger _log = Logger('AndroidAutoTlsClient');
  AndroidAutoTlsClient({
    required this.transport,
    required this.identityStore,
    openssl.OpenSSL? openSsl,
  }) : _openSsl = openSsl ?? openssl.OpenSSL();

  final SslHandshakeTransport transport;
  final HeadUnitIdentity identityStore;
  final openssl.OpenSSL _openSsl;

  Pointer<openssl.SSL_CTX> _context = nullptr;
  Pointer<openssl.SSL> _ssl = nullptr;
  Pointer<openssl.BIO> _readBio = nullptr;
  Pointer<openssl.BIO> _writeBio = nullptr;

  StreamSubscription<Uint8List>? _subscription;
  final Completer<void> _handshakeCompleter = Completer<void>();

  Future<void> _queue = Future<void>.value();
  bool _started = false;
  bool _connected = false;
  bool _closed = false;
  bool _connectCalled = false;

  bool get isConnected => _connected;

  /// Initializes OpenSSL and waits until the TLS handshake completes.
  Future<void> connect({Duration timeout = const Duration(seconds: 20)}) async {
    if (_started) {
      throw StateError('TLS handshake has already been started.');
    }

    _started = true;
    _connectCalled = true;

    try {
      await _initialize();

      _subscription = transport.incomingTlsBytes.listen(
        (Uint8List bytes) {
          _enqueue(() async {
            if (bytes.isEmpty || _closed) {
              return;
            }

            _log.fine('[TLS] Received ${bytes.length} TLS bytes.');
            _writeToBio(_readBio, bytes);
            await _driveHandshake();
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!_handshakeCompleter.isCompleted) {
            _handshakeCompleter.completeError(error, stackTrace);
          }
        },
        onDone: () {
          _log.warning('[TLS] Phone closed the incoming TLS stream.');
          _log.info('[TLS] Connected=$_connected');

          if (!_connected && !_handshakeCompleter.isCompleted) {
            _handshakeCompleter.completeError(
              StateError(
                'Phone closed the TLS stream while OpenSSL wanted more data.',
              ),
            );
          }
        },
        cancelOnError: false,
      );

      _enqueue(_driveHandshake);

      await _handshakeCompleter.future.timeout(timeout);
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<void> _initialize() async {
    final String? certificatePem = await identityStore.readCertificate();
    final String? privateKeyPem = await identityStore.readPrivateKey();

    if (certificatePem == null || certificatePem.trim().isEmpty) {
      throw StateError('No client certificate is stored.');
    }
    if (privateKeyPem == null || privateKeyPem.trim().isEmpty) {
      throw StateError('No client private key is stored.');
    }

    final openssl.OpenSslFfi ffi = _openSsl.bindings;

    final Pointer<openssl.SSL_METHOD> method = _openSsl
        .lookup<Pointer<openssl.SSL_METHOD> Function()>('TLS_client_method')
        .asFunction<Pointer<openssl.SSL_METHOD> Function()>()();

    _context = _createContext(method);
    if (_context == nullptr) {
      throw StateError('SSL_CTX_new failed.');
    }

    // SSL_CTX_ctrl commands:
    // SSL_CTRL_SET_MIN_PROTO_VERSION = 123
    // SSL_CTRL_SET_MAX_PROTO_VERSION = 124
    // TLS1_2_VERSION = 0x0303
    //
    // Windows uses a 32-bit C long, matching the int argument here.
    final int Function(Pointer<openssl.SSL_CTX>, int, int, Pointer<Void>)
    setContextOption = _openSsl
        .lookup<
          Int Function(Pointer<openssl.SSL_CTX>, Int, Int, Pointer<Void>)
        >('SSL_CTX_ctrl')
        .asFunction<
          int Function(Pointer<openssl.SSL_CTX>, int, int, Pointer<Void>)
        >();

    if (setContextOption(_context, 123, 0x0303, nullptr) != 1) {
      throw StateError('Failed to set the minimum TLS version to 1.2.');
    }
    if (setContextOption(_context, 124, 0x0303, nullptr) != 1) {
      throw StateError('Failed to set the maximum TLS version to 1.2.');
    }

    final Pointer<openssl.X509> certificate = _readCertificate(certificatePem);
    final Pointer<openssl.EVP_PKEY> privateKey = _readPrivateKey(privateKeyPem);

    try {
      final int Function(Pointer<openssl.SSL_CTX>, Pointer<openssl.X509>)
      useCertificate = _openSsl
          .lookup<
            Int Function(Pointer<openssl.SSL_CTX>, Pointer<openssl.X509>)
          >('SSL_CTX_use_certificate')
          .asFunction<
            int Function(Pointer<openssl.SSL_CTX>, Pointer<openssl.X509>)
          >();

      final int Function(Pointer<openssl.SSL_CTX>, Pointer<openssl.EVP_PKEY>)
      usePrivateKey = _openSsl
          .lookup<
            Int Function(Pointer<openssl.SSL_CTX>, Pointer<openssl.EVP_PKEY>)
          >('SSL_CTX_use_PrivateKey')
          .asFunction<
            int Function(Pointer<openssl.SSL_CTX>, Pointer<openssl.EVP_PKEY>)
          >();

      final int Function(Pointer<openssl.SSL_CTX>) checkPrivateKey = _openSsl
          .lookup<Int Function(Pointer<openssl.SSL_CTX>)>(
            'SSL_CTX_check_private_key',
          )
          .asFunction<int Function(Pointer<openssl.SSL_CTX>)>();

      if (useCertificate(_context, certificate) != 1) {
        throw StateError('OpenSSL rejected the client certificate.');
      }
      if (usePrivateKey(_context, privateKey) != 1) {
        throw StateError('OpenSSL rejected the client private key.');
      }
      if (checkPrivateKey(_context) != 1) {
        throw StateError(
          'The client certificate and private key do not match.',
        );
      }
    } finally {
      _openSsl
          .lookup<Void Function(Pointer<openssl.X509>)>('X509_free')
          .asFunction<void Function(Pointer<openssl.X509>)>()(certificate);

      _openSsl
          .lookup<Void Function(Pointer<openssl.EVP_PKEY>)>('EVP_PKEY_free')
          .asFunction<void Function(Pointer<openssl.EVP_PKEY>)>()(privateKey);
    }

    _ssl = _createSsl(_context);
    if (_ssl == nullptr) {
      throw StateError('SSL_new failed.');
    }

    _readBio = ffi.BIO_new(ffi.BIO_s_mem());
    _writeBio = ffi.BIO_new(ffi.BIO_s_mem());

    if (_readBio == nullptr || _writeBio == nullptr) {
      throw StateError('Failed to allocate TLS memory BIOs.');
    }

    _setBio(_ssl, _readBio, _writeBio);
    _setConnectState(_ssl);
  }

  Pointer<openssl.X509> _readCertificate(String pem) {
    final Pointer<openssl.BIO> bio = _bioFromString(pem);

    try {
      return _openSsl
          .lookup<
            Pointer<openssl.X509> Function(
              Pointer<openssl.BIO>,
              Pointer<Pointer<openssl.X509>>,
              Pointer<Void>,
              Pointer<Void>,
            )
          >('PEM_read_bio_X509')
          .asFunction<
            Pointer<openssl.X509> Function(
              Pointer<openssl.BIO>,
              Pointer<Pointer<openssl.X509>>,
              Pointer<Void>,
              Pointer<Void>,
            )
          >()(bio, nullptr.cast<Pointer<openssl.X509>>(), nullptr, nullptr);
    } finally {
      _openSsl.bindings.BIO_free(bio);
    }
  }

  Pointer<openssl.EVP_PKEY> _readPrivateKey(String pem) {
    final Pointer<openssl.BIO> bio = _bioFromString(pem);

    try {
      return _openSsl
          .lookup<
            Pointer<openssl.EVP_PKEY> Function(
              Pointer<openssl.BIO>,
              Pointer<Pointer<openssl.EVP_PKEY>>,
              Pointer<Void>,
              Pointer<Void>,
            )
          >('PEM_read_bio_PrivateKey')
          .asFunction<
            Pointer<openssl.EVP_PKEY> Function(
              Pointer<openssl.BIO>,
              Pointer<Pointer<openssl.EVP_PKEY>>,
              Pointer<Void>,
              Pointer<Void>,
            )
          >()(bio, nullptr.cast<Pointer<openssl.EVP_PKEY>>(), nullptr, nullptr);
    } finally {
      _openSsl.bindings.BIO_free(bio);
    }
  }

  Pointer<openssl.BIO> _bioFromString(String value) {
    final Uint8List bytes = Uint8List.fromList(value.codeUnits);
    final openssl.OpenSslFfi ffi = _openSsl.bindings;

    final Pointer<openssl.BIO> bio = ffi.BIO_new(ffi.BIO_s_mem());
    if (bio == nullptr) {
      throw StateError('Failed to allocate a PEM BIO.');
    }

    try {
      _writeToBio(bio, bytes);
      return bio;
    } catch (_) {
      ffi.BIO_free(bio);
      rethrow;
    }
  }

  void _writeToBio(Pointer<openssl.BIO> bio, Uint8List bytes) {
    final Pointer<Uint8> buffer = calloc<Uint8>(bytes.length);

    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final int written = _openSsl.bindings.BIO_write(
        bio,
        buffer.cast(),
        bytes.length,
      );

      if (written != bytes.length) {
        throw StateError('OpenSSL BIO_write failed.');
      }
    } finally {
      calloc.free(buffer);
    }
  }

  Future<void> _driveHandshake() async {
    if (_closed || _connected) {
      return;
    }

    for (int attempt = 0; attempt < 32; attempt++) {
      final int result = _doHandshake(_ssl);

      // Get the error immediately after SSL_do_handshake.
      final int error = result == 1 ? 0 : _getSslError(_ssl, result);

      _log.fine('[TLS] SSL_do_handshake result=$result, error=$error');

      await _flushOutgoing();

      if (result == 1) {
        _connected = true;
        _log.info('[TLS] Handshake completed successfully.');
        if (!_handshakeCompleter.isCompleted) {
          _handshakeCompleter.complete();
        }
        return;
      }

      if (error == 2) {
        // SSL_ERROR_WANT_READ: wait for more incoming TLS bytes.
        return;
      }

      if (error == 3) {
        // SSL_ERROR_WANT_WRITE: retry after flushing output.
        continue;
      }

      throw StateError(
        'TLS handshake failed (SSL_get_error=$error, result=$result).',
      );
    }

    throw StateError('TLS handshake exceeded the retry limit.');
  }

  Future<void> _flushOutgoing() async {
    const int bioCtrlPending = 10;
    final openssl.OpenSslFfi ffi = _openSsl.bindings;

    while (true) {
      final int pending = ffi.BIO_ctrl(_writeBio, bioCtrlPending, 0, nullptr);

      if (pending <= 0) {
        return;
      }

      final int length = pending > 16384 ? 16384 : pending;
      final Pointer<Uint8> buffer = calloc<Uint8>(length);

      try {
        final int read = ffi.BIO_read(_writeBio, buffer.cast(), length);

        if (read <= 0) {
          throw StateError('Failed to read outgoing TLS bytes.');
        }

        final Uint8List bytes = Uint8List.fromList(buffer.asTypedList(read));
        await transport.sendTlsBytes(bytes);
      } finally {
        calloc.free(buffer);
      }
    }
  }

  void _enqueue(Future<void> Function() operation) {
    _queue = _queue.then((_) => operation()).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _log.severe('[TLS] TLS operation failed.', error, stackTrace);

      if (!_handshakeCompleter.isCompleted) {
        _handshakeCompleter.completeError(error, stackTrace);
      }
    });
  }

  Pointer<openssl.SSL_CTX> _createContext(Pointer<openssl.SSL_METHOD> method) {
    return _openSsl
        .lookup<Pointer<openssl.SSL_CTX> Function(Pointer<openssl.SSL_METHOD>)>(
          'SSL_CTX_new',
        )
        .asFunction<
          Pointer<openssl.SSL_CTX> Function(Pointer<openssl.SSL_METHOD>)
        >()(method);
  }

  Pointer<openssl.SSL> _createSsl(Pointer<openssl.SSL_CTX> context) {
    return _openSsl
        .lookup<Pointer<openssl.SSL> Function(Pointer<openssl.SSL_CTX>)>(
          'SSL_new',
        )
        .asFunction<Pointer<openssl.SSL> Function(Pointer<openssl.SSL_CTX>)>()(
      context,
    );
  }

  /// Encrypts plaintext into TLS records and returns the resulting bytes.
  ///
  /// Does not send the returned bytes over the Android Auto connection.
  Future<Uint8List> encryptApplicationData(Uint8List plaintext) async {
    if (!_connected || _closed || _ssl == nullptr) {
      throw StateError('TLS is not connected.');
    }

    final Completer<Uint8List> completer = Completer<Uint8List>();

    _enqueue(() async {
      try {
        if (!_connected || _closed || _ssl == nullptr) {
          throw StateError('TLS connection is closed.');
        }

        _sslWriteApplicationData(plaintext);

        // Drain the BIO directly. Do not call _flushOutgoing() here,
        // because that method sends the bytes through SSL_HANDSHAKE.
        completer.complete(_drainWriteBio());
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
        rethrow;
      }
    });

    return completer.future;
  }

  /// Decrypts incoming TLS records into application data.
  ///
  /// The caller must supply only the TLS bytes belonging to this
  /// application's encrypted payload.
  Future<Uint8List> decryptApplicationData(Uint8List encrypted) async {
    if (!_connected || _closed || _ssl == nullptr) {
      throw StateError('TLS is not connected.');
    }

    final Completer<Uint8List> completer = Completer<Uint8List>();

    _enqueue(() async {
      try {
        if (!_connected || _closed || _ssl == nullptr) {
          throw StateError('TLS connection is closed.');
        }

        _writeToBio(_readBio, encrypted);
        final Uint8List plaintext = _sslReadAvailable();
        await _flushOutgoing();

        completer.complete(plaintext);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
        rethrow;
      }
    });

    return completer.future;
  }

  Uint8List _sslWriteApplicationData(Uint8List plaintext) {
    if (plaintext.isEmpty) {
      return Uint8List(0);
    }

    final Pointer<Uint8> buffer = calloc<Uint8>(plaintext.length);

    try {
      buffer.asTypedList(plaintext.length).setAll(0, plaintext);

      final int written = _openSsl
          .lookup<Int Function(Pointer<openssl.SSL>, Pointer<Void>, Int)>(
            'SSL_write',
          )
          .asFunction<
            int Function(Pointer<openssl.SSL>, Pointer<Void>, int)
          >()(_ssl, buffer.cast<Void>(), plaintext.length);

      if (written <= 0) {
        final int error = _getSslError(_ssl, written);
        throw StateError(
          'SSL_write failed (SSL_get_error=$error, result=$written).',
        );
      }

      if (written != plaintext.length) {
        throw StateError(
          'SSL_write wrote $written of ${plaintext.length} bytes.',
        );
      }

      return Uint8List.fromList(plaintext);
    } finally {
      calloc.free(buffer);
    }
  }

  Uint8List _sslReadAvailable() {
    const int sslErrorWantRead = 2;
    const int sslErrorWantWrite = 3;
    const int sslErrorZeroReturn = 6;

    final BytesBuilder output = BytesBuilder(copy: false);

    for (int attempt = 0; attempt < 32; attempt++) {
      const int chunkSize = 16384;
      final Pointer<Uint8> buffer = calloc<Uint8>(chunkSize);

      try {
        final int read = _openSsl
            .lookup<Int Function(Pointer<openssl.SSL>, Pointer<Void>, Int)>(
              'SSL_read',
            )
            .asFunction<
              int Function(Pointer<openssl.SSL>, Pointer<Void>, int)
            >()(_ssl, buffer.cast<Void>(), chunkSize);

        if (read > 0) {
          output.add(Uint8List.fromList(buffer.asTypedList(read)));
          continue;
        }

        final int error = _getSslError(_ssl, read);

        if (error == sslErrorWantRead || error == sslErrorZeroReturn) {
          return output.takeBytes();
        }

        if (error == sslErrorWantWrite) {
          // The caller flushes pending TLS output after this operation.
          return output.takeBytes();
        }

        throw StateError(
          'SSL_read failed (SSL_get_error=$error, result=$read).',
        );
      } finally {
        calloc.free(buffer);
      }
    }

    throw StateError('SSL_read exceeded the retry limit.');
  }

  Uint8List _drainWriteBio() {
    const int bioCtrlPending = 10;
    final BytesBuilder output = BytesBuilder(copy: false);
    final openssl.OpenSslFfi ffi = _openSsl.bindings;

    while (true) {
      final int pending = ffi.BIO_ctrl(_writeBio, bioCtrlPending, 0, nullptr);

      if (pending <= 0) {
        return output.takeBytes();
      }

      final int length = pending > 16384 ? 16384 : pending;
      final Pointer<Uint8> buffer = calloc<Uint8>(length);

      try {
        final int read = ffi.BIO_read(_writeBio, buffer.cast(), length);

        if (read <= 0) {
          throw StateError('Failed to drain the TLS write BIO.');
        }

        output.add(Uint8List.fromList(buffer.asTypedList(read)));
      } finally {
        calloc.free(buffer);
      }
    }
  }

  void _setBio(
    Pointer<openssl.SSL> ssl,
    Pointer<openssl.BIO> readBio,
    Pointer<openssl.BIO> writeBio,
  ) {
    _openSsl
        .lookup<
          Void Function(
            Pointer<openssl.SSL>,
            Pointer<openssl.BIO>,
            Pointer<openssl.BIO>,
          )
        >('SSL_set_bio')
        .asFunction<
          void Function(
            Pointer<openssl.SSL>,
            Pointer<openssl.BIO>,
            Pointer<openssl.BIO>,
          )
        >()(ssl, readBio, writeBio);
  }

  void _setConnectState(Pointer<openssl.SSL> ssl) {
    _openSsl
        .lookup<Void Function(Pointer<openssl.SSL>)>('SSL_set_connect_state')
        .asFunction<void Function(Pointer<openssl.SSL>)>()(ssl);
  }

  int _doHandshake(Pointer<openssl.SSL> ssl) {
    return _openSsl
        .lookup<Int Function(Pointer<openssl.SSL>)>('SSL_do_handshake')
        .asFunction<int Function(Pointer<openssl.SSL>)>()(ssl);
  }

  int _getSslError(Pointer<openssl.SSL> ssl, int result) {
    return _openSsl
        .lookup<Int Function(Pointer<openssl.SSL>, Int)>('SSL_get_error')
        .asFunction<int Function(Pointer<openssl.SSL>, int)>()(ssl, result);
  }

  void _freeSsl(Pointer<openssl.SSL> ssl) {
    _openSsl
        .lookup<Void Function(Pointer<openssl.SSL>)>('SSL_free')
        .asFunction<void Function(Pointer<openssl.SSL>)>()(ssl);
  }

  void _freeContext(Pointer<openssl.SSL_CTX> context) {
    _openSsl
        .lookup<Void Function(Pointer<openssl.SSL_CTX>)>('SSL_CTX_free')
        .asFunction<void Function(Pointer<openssl.SSL_CTX>)>()(context);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;
    _connected = false;

    await _subscription?.cancel();
    _subscription = null;

    if (_ssl != nullptr) {
      _freeSsl(_ssl);
      _ssl = nullptr;
      _readBio = nullptr;
      _writeBio = nullptr;
    } else {
      if (_readBio != nullptr) {
        _openSsl.bindings.BIO_free(_readBio);
        _readBio = nullptr;
      }
      if (_writeBio != nullptr) {
        _openSsl.bindings.BIO_free(_writeBio);
        _writeBio = nullptr;
      }
    }

    if (_context != nullptr) {
      _freeContext(_context);
      _context = nullptr;
    }

    if (_connectCalled && !_handshakeCompleter.isCompleted) {
      _handshakeCompleter.completeError(
        StateError('TLS handshake was closed before completion.'),
      );
    }
  }
}
