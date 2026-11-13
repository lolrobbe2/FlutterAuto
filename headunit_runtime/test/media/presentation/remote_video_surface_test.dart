import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headunit_shared/headunit_shared_io.dart';
import 'package:headunit_runtime/headunit_runtime.dart';

class _FakeVideoDecoder implements VideoDecoder {
  @override
  final int textureId = 42;

  final List<EncodedVideoFrame> decodedFrames = <EncodedVideoFrame>[];
  bool disposed = false;

  @override
  Future<void> decode(EncodedVideoFrame frame) async {
    decodedFrames.add(frame);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders a texture and forwards normalized pointer input', (
    WidgetTester tester,
  ) async {
    const String token = '0123456789abcdef0123456789abcdef';
    LocalMediaServer? server;
    MediaStreamClient? client;
    MediaStreamConnection? hostConnection;
    final _FakeVideoDecoder decoder = _FakeVideoDecoder();
    final List<ApplicationPointerEvent> pointerEvents =
        <ApplicationPointerEvent>[];

    await tester.runAsync(() async {
      server = await LocalMediaServer.bind(token: token);
      final Future<MediaStreamConnection> accepted = server!.connections.first;
      client = await MediaStreamClient.connect(
        host: server!.host,
        port: server!.port,
        token: token,
      );
      hostConnection = await accepted;
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 120,
            child: RemoteVideoSurface(
              connection: hostConnection!,
              decoderFactory: (VideoStreamConfiguration configuration) async {
                expect(configuration.width, 800);
                expect(configuration.height, 480);
                return decoder;
              },
              onPointerEvent: pointerEvents.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Texture), findsOneWidget);

    final TestGesture gesture = await tester.startGesture(
      const Offset(50, 30),
      pointer: 7,
    );
    await gesture.moveTo(const Offset(100, 60));
    await gesture.up();

    expect(pointerEvents, hasLength(3));
    expect(pointerEvents[0].pointerId, 7);
    expect(pointerEvents[0].phase, ApplicationPointerPhase.down);
    expect(pointerEvents[0].x, closeTo(0.25, 0.01));
    expect(pointerEvents[0].y, closeTo(0.25, 0.01));
    expect(pointerEvents[1].phase, ApplicationPointerPhase.move);
    expect(pointerEvents[1].x, closeTo(0.5, 0.01));
    expect(pointerEvents[1].y, closeTo(0.5, 0.01));
    expect(pointerEvents[2].phase, ApplicationPointerPhase.up);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
      expect(decoder.disposed, isTrue);
      await client!.close();
      await server!.close();
    });
  });

  testWidgets('passes encoded access units to the decoder', (
    WidgetTester tester,
  ) async {
    const String token = 'abcdef0123456789abcdef0123456789';
    LocalMediaServer? server;
    MediaStreamClient? client;
    MediaStreamConnection? hostConnection;
    final _FakeVideoDecoder decoder = _FakeVideoDecoder();

    await tester.runAsync(() async {
      server = await LocalMediaServer.bind(token: token);
      final Future<MediaStreamConnection> accepted = server!.connections.first;
      client = await MediaStreamClient.connect(
        host: server!.host,
        port: server!.port,
        token: token,
      );
      hostConnection = await accepted;
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 200,
          height: 120,
          child: RemoteVideoSurface(
            connection: hostConnection!,
            decoderFactory: (_) async => decoder,
            onPointerEvent: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      await client!.sendFrame(
        EncodedVideoFrame(
          sequenceNumber: 0,
          presentationTimeMicros: 0,
          isKeyFrame: true,
          data: Uint8List.fromList(<int>[0, 0, 0, 1, 0x65]),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();

    expect(decoder.decodedFrames, hasLength(1));
    expect(decoder.decodedFrames.single.isKeyFrame, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await client!.close();
      await server!.close();
    });
  });
}
