import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_auto/headunit/message_assembler.dart';
import 'package:flutter_auto/headunit/protocol_frame.dart';
import 'package:flutter_auto/headunit/protocol_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageAssembler', () {
    late MessageAssembler assembler;

    setUp(() {
      assembler = const MessageAssembler();
    });

    ProtocolFrame createFrame({
      required int channel,
      required FrameType frameType,
      required List<int> payload,
      int? totalMessageSize,
      MessageType messageType = MessageType.control,
      EncryptionType encryptionType = EncryptionType.plain,
    }) {
      return ProtocolFrame(
        channel: channel,
        frameType: frameType,
        messageType: messageType,
        encryptionType: encryptionType,
        payload: Uint8List.fromList(payload),
        totalMessageSize: totalMessageSize,
      );
    }

    test('emits a complete BULK message', () async {
      final ProtocolFrame frame = createFrame(
        channel: 0,
        frameType: FrameType.bulk,
        payload: <int>[1, 2, 3],
      );

      final List<ProtocolMessage> messages = await assembler
          .bind(Stream<ProtocolFrame>.value(frame))
          .toList();

      expect(messages, hasLength(1));
      expect(messages[0].channel, 0);
      expect(messages[0].payload, equals(<int>[1, 2, 3]));
      expect(messages[0].messageType, MessageType.control);
      expect(messages[0].encryptionType, EncryptionType.plain);
    });

    test('reassembles FIRST followed by LAST', () async {
      final List<ProtocolFrame> frames = <ProtocolFrame>[
        createFrame(
          channel: 1,
          frameType: FrameType.first,
          payload: <int>[1, 2],
          totalMessageSize: 4,
        ),
        createFrame(
          channel: 1,
          frameType: FrameType.last,
          payload: <int>[3, 4],
        ),
      ];

      final List<ProtocolMessage> messages = await assembler
          .bind(Stream<ProtocolFrame>.fromIterable(frames))
          .toList();

      expect(messages, hasLength(1));
      expect(messages[0].channel, 1);
      expect(messages[0].payload, equals(<int>[1, 2, 3, 4]));
    });

    test('reassembles FIRST, MIDDLE, and LAST', () async {
      final List<ProtocolFrame> frames = <ProtocolFrame>[
        createFrame(
          channel: 1,
          frameType: FrameType.first,
          payload: <int>[10, 20],
          totalMessageSize: 5,
        ),
        createFrame(
          channel: 1,
          frameType: FrameType.middle,
          payload: <int>[30],
        ),
        createFrame(
          channel: 1,
          frameType: FrameType.last,
          payload: <int>[40, 50],
        ),
      ];

      final List<ProtocolMessage> messages = await assembler
          .bind(Stream<ProtocolFrame>.fromIterable(frames))
          .toList();

      expect(messages, hasLength(1));
      expect(messages[0].payload, equals(<int>[10, 20, 30, 40, 50]));
    });

    test('reassembles interleaved messages on different channels', () async {
      final List<ProtocolFrame> frames = <ProtocolFrame>[
        createFrame(
          channel: 1,
          frameType: FrameType.first,
          payload: <int>[1],
          totalMessageSize: 2,
        ),
        createFrame(
          channel: 2,
          frameType: FrameType.first,
          payload: <int>[10],
          totalMessageSize: 3,
        ),
        createFrame(channel: 1, frameType: FrameType.last, payload: <int>[2]),
        createFrame(
          channel: 2,
          frameType: FrameType.last,
          payload: <int>[20, 30],
        ),
      ];

      final List<ProtocolMessage> messages = await assembler
          .bind(Stream<ProtocolFrame>.fromIterable(frames))
          .toList();

      expect(messages, hasLength(2));
      expect(messages[0].channel, 1);
      expect(messages[0].payload, equals(<int>[1, 2]));
      expect(messages[1].channel, 2);
      expect(messages[1].payload, equals(<int>[10, 20, 30]));
    });

    test('preserves message metadata from FIRST', () async {
      final List<ProtocolFrame> frames = <ProtocolFrame>[
        createFrame(
          channel: 3,
          frameType: FrameType.first,
          payload: <int>[1],
          totalMessageSize: 2,
          messageType: MessageType.specific,
          encryptionType: EncryptionType.encrypted,
        ),
        createFrame(
          channel: 3,
          frameType: FrameType.last,
          payload: <int>[2],
          messageType: MessageType.specific,
          encryptionType: EncryptionType.encrypted,
        ),
      ];

      final List<ProtocolMessage> messages = await assembler
          .bind(Stream<ProtocolFrame>.fromIterable(frames))
          .toList();

      expect(messages.single.messageType, MessageType.specific);
      expect(messages.single.encryptionType, EncryptionType.encrypted);
    });

    test('rejects MIDDLE without FIRST', () async {
      final ProtocolFrame frame = createFrame(
        channel: 1,
        frameType: FrameType.middle,
        payload: <int>[1],
      );

      await expectLater(
        assembler.bind(Stream<ProtocolFrame>.value(frame)).toList(),
        throwsFormatException,
      );
    });

    test('rejects LAST without FIRST', () async {
      final ProtocolFrame frame = createFrame(
        channel: 1,
        frameType: FrameType.last,
        payload: <int>[1],
      );

      await expectLater(
        assembler.bind(Stream<ProtocolFrame>.value(frame)).toList(),
        throwsFormatException,
      );
    });

    test('rejects BULK while a fragmented message is incomplete', () async {
      final List<ProtocolFrame> frames = <ProtocolFrame>[
        createFrame(
          channel: 1,
          frameType: FrameType.first,
          payload: <int>[1],
          totalMessageSize: 2,
        ),
        createFrame(channel: 1, frameType: FrameType.bulk, payload: <int>[9]),
      ];

      await expectLater(
        assembler.bind(Stream<ProtocolFrame>.fromIterable(frames)).toList(),
        throwsFormatException,
      );
    });

    test('rejects a fragmented message with an incorrect final size', () async {
      final List<ProtocolFrame> frames = <ProtocolFrame>[
        createFrame(
          channel: 1,
          frameType: FrameType.first,
          payload: <int>[1],
          totalMessageSize: 3,
        ),
        createFrame(channel: 1, frameType: FrameType.last, payload: <int>[2]),
      ];

      await expectLater(
        assembler.bind(Stream<ProtocolFrame>.fromIterable(frames)).toList(),
        throwsFormatException,
      );
    });

    test('rejects a fragment that exceeds the declared size', () async {
      final List<ProtocolFrame> frames = <ProtocolFrame>[
        createFrame(
          channel: 1,
          frameType: FrameType.first,
          payload: <int>[1],
          totalMessageSize: 2,
        ),
        createFrame(
          channel: 1,
          frameType: FrameType.middle,
          payload: <int>[2, 3],
        ),
      ];

      await expectLater(
        assembler.bind(Stream<ProtocolFrame>.fromIterable(frames)).toList(),
        throwsFormatException,
      );
    });

    test('rejects a second FIRST on the same channel', () async {
      final List<ProtocolFrame> frames = <ProtocolFrame>[
        createFrame(
          channel: 1,
          frameType: FrameType.first,
          payload: <int>[1],
          totalMessageSize: 3,
        ),
        createFrame(
          channel: 1,
          frameType: FrameType.first,
          payload: <int>[2],
          totalMessageSize: 3,
        ),
      ];

      await expectLater(
        assembler.bind(Stream<ProtocolFrame>.fromIterable(frames)).toList(),
        throwsFormatException,
      );
    });

    test('rejects a message type change during fragmentation', () async {
      final List<ProtocolFrame> frames = <ProtocolFrame>[
        createFrame(
          channel: 1,
          frameType: FrameType.first,
          payload: <int>[1],
          totalMessageSize: 2,
          messageType: MessageType.control,
        ),
        createFrame(
          channel: 1,
          frameType: FrameType.last,
          payload: <int>[2],
          messageType: MessageType.specific,
        ),
      ];

      await expectLater(
        assembler.bind(Stream<ProtocolFrame>.fromIterable(frames)).toList(),
        throwsFormatException,
      );
    });

    test('rejects an incomplete message when the stream ends', () async {
      final ProtocolFrame frame = createFrame(
        channel: 1,
        frameType: FrameType.first,
        payload: <int>[1],
        totalMessageSize: 2,
      );

      await expectLater(
        assembler.bind(Stream<ProtocolFrame>.value(frame)).toList(),
        throwsFormatException,
      );
    });
  });
}
