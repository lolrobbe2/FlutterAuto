import 'dart:typed_data';

import 'package:flutter_auto_core/flutter_auto_core.dart';
import 'package:flutter_test/flutter_test.dart';

// Replace with the actual paths in your project.


void main() {
  group('AndroidAutoTlsClient', () {
    late AndroidAutoTlsClient client;

    setUp(() {
      // These tests only verify behavior before TLS initialization.
      // They do not need a connected phone.
      client = AndroidAutoTlsClient(
        transport: _UnusedTransport(),
        identityStore: _UnusedIdentity(),
      );
    });

    test('is not connected before connect()', () {
      expect(client.isConnected, isFalse);
    });

    test('rejects encryption before TLS connects', () async {
      await expectLater(
        client.encryptApplicationData(Uint8List.fromList(<int>[1, 2, 3])),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects decryption before TLS connects', () async {
      await expectLater(
        client.decryptApplicationData(
          Uint8List.fromList(<int>[23, 3, 3, 0, 1]),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('close() is safe before connect()', () async {
      await client.close();
      await client.close();

      expect(client.isConnected, isFalse);
    });
  });
}

/// These fakes are placeholders. Implement them using the actual constructors
/// and interfaces in your project, or use Mocktail to mock these dependencies.
class _UnusedTransport implements SslHandshakeTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedIdentity implements HeadUnitIdentity {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
