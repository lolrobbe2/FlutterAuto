import 'package:example/media_demo/h264_annex_b_parser.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('H264AnnexBParser', () {
    test('groups AUD-delimited NAL units into access units', () {
      final Uint8List stream = Uint8List.fromList(<int>[
        // SPS and PPS are retained with the first access unit.
        0, 0, 0, 1, 0x67, 0x64,
        0, 0, 1, 0x68, 0xee,
        0, 0, 0, 1, 0x09, 0xf0,
        0, 0, 1, 0x65, 0x88,
        0, 0, 0, 1, 0x09, 0xf0,
        0, 0, 1, 0x41, 0x99,
      ]);

      final List<H264AccessUnit> accessUnits = H264AnnexBParser.parse(stream);

      expect(accessUnits, hasLength(2));
      expect(accessUnits.first.isKeyFrame, isTrue);
      expect(accessUnits.last.isKeyFrame, isFalse);
      expect(accessUnits.first.data, containsAllInOrder(<int>[0, 0, 0, 1]));
      expect(accessUnits.last.data, containsAllInOrder(<int>[0, 0, 0, 1]));
    });

    test('rejects streams without AUD delimiters', () {
      final Uint8List stream = Uint8List.fromList(<int>[
        0,
        0,
        0,
        1,
        0x65,
        0x88,
      ]);

      expect(() => H264AnnexBParser.parse(stream), throwsFormatException);
    });

    test('requires the first access unit to be an IDR', () {
      final Uint8List stream = Uint8List.fromList(<int>[
        0,
        0,
        0,
        1,
        0x09,
        0xf0,
        0,
        0,
        1,
        0x41,
        0x99,
      ]);

      expect(() => H264AnnexBParser.parse(stream), throwsFormatException);
    });

    test(
      'bundled visual sample contains 120 frames and periodic IDRs',
      () async {
        final ByteData asset = await rootBundle.load(
          'assets/remote_video_demo.h264',
        );
        final Uint8List bytes = asset.buffer.asUint8List(
          asset.offsetInBytes,
          asset.lengthInBytes,
        );

        final List<H264AccessUnit> accessUnits = H264AnnexBParser.parse(bytes);

        expect(accessUnits, hasLength(120));
        expect(accessUnits.first.isKeyFrame, isTrue);
        expect(
          accessUnits.where((H264AccessUnit unit) => unit.isKeyFrame),
          hasLength(3),
        );
      },
    );
  });
}
