import 'package:headunit_shared/headunit_shared.dart';
import 'package:test/test.dart';

void main() {
  group('HeadunitUiPage', () {
    test(
      'round-trips a nested declarative page without serializing callbacks',
      () {
        final HeadunitUiPage page = HeadunitUiPage(
          title: 'Music',
          subtitle: 'Now playing',
          body: HeadunitUiColumn(
            children: <HeadunitUiComponent>[
              HeadunitUiText(text: 'Albums', style: HeadunitUiTextStyle.title),
              HeadunitUiCarousel(
                items: <HeadunitUiCarouselItem>[
                  HeadunitUiCarouselItem(
                    id: 'album-1',
                    title: 'Road trip',
                    action: HeadunitUiAction(
                      id: 'open-road-trip',
                      onInvoke: () {},
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        final Map<String, Object?> encoded = page.toJson();
        final HeadunitUiPage decoded = HeadunitUiPage.fromJson(encoded);

        expect(decoded.title, 'Music');
        expect(decoded.subtitle, 'Now playing');
        expect(decoded.body, isA<HeadunitUiColumn>());
        expect(decoded.actions.single.id, 'open-road-trip');
        expect(decoded.actions.single.onInvoke, isNull);
      },
    );

    test('rejects unknown schema versions', () {
      expect(
        () => HeadunitUiPage.fromJson(<String, Object?>{
          'schemaVersion': 99,
          'title': 'Unsupported',
          'body': <String, Object?>{'type': 'text', 'text': 'Nope'},
        }),
        throwsFormatException,
      );
    });

    test('rejects unsupported image URL schemes', () {
      expect(
        () => HeadunitUiImage(url: 'file:///private/image.png'),
        throwsArgumentError,
      );
    });

    test('rejects blank semantic text', () {
      expect(
        () => HeadunitUiPage(
          title: '  ',
          body: HeadunitUiText(text: 'Body'),
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid progress values', () {
      expect(() => HeadunitUiProgress(value: 1.5), throwsArgumentError);
    });
  });
}
