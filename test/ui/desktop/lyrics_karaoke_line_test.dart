import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/ui/desktop/lyrics_karaoke_line.dart';

void main() {
  group('calculateMarqueeOffset unit tests', () {
    test('returns 0.0 when textWidth <= availableWidth', () {
      expect(
        calculateMarqueeOffset(
          textWidth: 300,
          availableWidth: 500,
          progress: 0.5,
        ),
        0.0,
      );
      expect(
        calculateMarqueeOffset(
          textWidth: 500,
          availableWidth: 500,
          progress: 1.0,
        ),
        0.0,
      );
      expect(
        LyricsKaraokeLine.calculateMarqueeOffset(
          textWidth: 100,
          availableWidth: 400,
          progress: 0.0,
        ),
        0.0,
      );
    });

    test('calculates correct scroll offset when textWidth > availableWidth', () {
      // textWidth = 1000, availableWidth = 700
      // maxScroll = 1000 - 700 + 32 = 332.0
      const textWidth = 1000.0;
      const availableWidth = 700.0;
      const expectedMaxScroll = 332.0;

      expect(
        calculateMarqueeOffset(
          textWidth: textWidth,
          availableWidth: availableWidth,
          progress: 0.0,
        ),
        0.0,
      );

      expect(
        calculateMarqueeOffset(
          textWidth: textWidth,
          availableWidth: availableWidth,
          progress: 0.5,
        ),
        -expectedMaxScroll * 0.5,
      );

      expect(
        calculateMarqueeOffset(
          textWidth: textWidth,
          availableWidth: availableWidth,
          progress: 1.0,
        ),
        -expectedMaxScroll,
      );
    });

    test('clamps progress below 0.0 and above 1.0', () {
      const textWidth = 1000.0;
      const availableWidth = 700.0;
      const expectedMaxScroll = 332.0;

      expect(
        calculateMarqueeOffset(
          textWidth: textWidth,
          availableWidth: availableWidth,
          progress: -0.5,
        ),
        0.0,
      );

      expect(
        calculateMarqueeOffset(
          textWidth: textWidth,
          availableWidth: availableWidth,
          progress: 1.5,
        ),
        -expectedMaxScroll,
      );
    });
  });

  group('ProgressClipper unit tests', () {
    test('clips correctly at 0.0, 0.5, and 1.0 progress', () {
      const clipper0 = ProgressClipper(progress: 0.0, textWidth: 200.0);
      expect(clipper0.getClip(const Size(200, 40)).width, 0.0);

      const clipperHalf = ProgressClipper(progress: 0.5, textWidth: 200.0);
      expect(clipperHalf.getClip(const Size(200, 40)).width, 100.0);

      const clipperFull = ProgressClipper(progress: 1.0, textWidth: 200.0);
      expect(clipperFull.getClip(const Size(200, 40)).width, 200.0);
    });

    test('shouldReclip responds to changes in progress and textWidth', () {
      const clipper1 = ProgressClipper(progress: 0.3, textWidth: 100.0);
      const clipperSame = ProgressClipper(progress: 0.3, textWidth: 100.0);
      const clipperDiffProg = ProgressClipper(progress: 0.4, textWidth: 100.0);
      const clipperDiffWidth = ProgressClipper(progress: 0.3, textWidth: 120.0);

      expect(clipperSame.shouldReclip(clipper1), isFalse);
      expect(clipperDiffProg.shouldReclip(clipper1), isTrue);
      expect(clipperDiffWidth.shouldReclip(clipper1), isTrue);
    });
  });

  group('LyricsKaraokeLine widget tests', () {
    testWidgets('renders text with decoration none without yellow double underlines', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: LyricsKaraokeLine(
            text: 'Hello World',
            fontSize: 24,
            playedColor: Colors.amber,
            unplayedColor: Colors.white,
            progress: 0.0,
            availableWidth: 500,
          ),
        ),
      );

      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(texts.length, 2);
      for (final t in texts) {
        expect(t.style?.decoration, TextDecoration.none);
      }
    });

    testWidgets('renders both unplayed base layer and played highlight layer', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: LyricsKaraokeLine(
            text: '双层歌词测试',
            fontSize: 28,
            playedColor: Color(0xFF00FFCC),
            unplayedColor: Color(0xFFFFFFFF),
            progress: 0.4,
            availableWidth: 600,
          ),
        ),
      );

      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(texts.length, 2);

      final baseText = texts[0];
      final highlightText = texts[1];

      // Base unplayed text
      expect(baseText.data, '双层歌词测试');
      expect(baseText.style?.color, const Color(0xFFFFFFFF));
      expect(baseText.style?.shadows, isNotNull);
      expect(baseText.style?.shadows!.length, 2);

      // Highlight played text
      expect(highlightText.data, '双层歌词测试');
      expect(highlightText.style?.color, const Color(0xFF00FFCC));
      expect(highlightText.style?.shadows, isNotNull);
      expect(highlightText.style?.shadows!.length, 2);

      // ClipRect wraps highlight text with ProgressClipper
      final clipFinder = find.descendant(
        of: find.byType(Stack),
        matching: find.byType(ClipRect),
      );
      expect(clipFinder, findsOneWidget);
      final clipRect = tester.widget<ClipRect>(clipFinder);
      expect(clipRect.clipper, isA<ProgressClipper>());
    });

    testWidgets('at progress 0.0 highlight layer width is 0', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: LyricsKaraokeLine(
            text: 'Progress Zero Test',
            fontSize: 24,
            playedColor: Colors.green,
            unplayedColor: Colors.white,
            progress: 0.0,
            availableWidth: 500,
          ),
        ),
      );

      final clipFinder = find.descendant(
        of: find.byType(Stack),
        matching: find.byType(ClipRect),
      );
      final clipRect = tester.widget<ClipRect>(clipFinder);
      final clipper = clipRect.clipper as ProgressClipper;
      expect(clipper.getClip(const Size(300, 30)).width, 0.0);
    });

    testWidgets('at progress 1.0 highlight layer width is 100% of textWidth', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: LyricsKaraokeLine(
            text: 'Progress One Test',
            fontSize: 24,
            playedColor: Colors.green,
            unplayedColor: Colors.white,
            progress: 1.0,
            availableWidth: 500,
          ),
        ),
      );

      final clipFinder = find.descendant(
        of: find.byType(Stack),
        matching: find.byType(ClipRect),
      );
      final clipRect = tester.widget<ClipRect>(clipFinder);
      final clipper = clipRect.clipper as ProgressClipper;
      expect(clipper.getClip(const Size(300, 30)).width, clipper.textWidth);
      expect(clipper.textWidth, greaterThan(0.0));
    });

    testWidgets('aligns text according to alignment when not overflow', (tester) async {
      for (final align in [TextAlign.center, TextAlign.left, TextAlign.right]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: LyricsKaraokeLine(
              text: 'Short',
              fontSize: 20,
              playedColor: Colors.amber,
              unplayedColor: Colors.white,
              progress: 0.5,
              availableWidth: 600,
              alignment: align,
            ),
          ),
        );

        final alignFinder = find.byType(Align);
        expect(alignFinder, findsOneWidget);
        final alignWidget = tester.widget<Align>(alignFinder);

        if (align == TextAlign.left) {
          expect(alignWidget.alignment, Alignment.centerLeft);
        } else if (align == TextAlign.right) {
          expect(alignWidget.alignment, Alignment.centerRight);
        } else {
          expect(alignWidget.alignment, Alignment.center);
        }
      }
    });

    testWidgets('smooth marquee translate when textWidth > availableWidth', (tester) async {
      const longText = '这是一段非常非常非常非常非常长的桌面歌词，肯定会超出容器的可用宽度';
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: LyricsKaraokeLine(
            text: longText,
            fontSize: 28,
            playedColor: Colors.amber,
            unplayedColor: Colors.white,
            progress: 0.5,
            availableWidth: 200, // Small available width to force overflow
          ),
        ),
      );

      final transformFinder = find.byType(Transform);
      expect(transformFinder, findsOneWidget);
      final transform = tester.widget<Transform>(transformFinder);
      final matrix = transform.transform;
      final translationX = matrix.getTranslation().x;
      // Scroll offset should be negative
      expect(translationX, lessThan(0.0));
    });

    testWidgets('handles empty string gracefully', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: LyricsKaraokeLine(
            text: '',
            fontSize: 24,
            playedColor: Colors.amber,
            unplayedColor: Colors.white,
            progress: 0.5,
            availableWidth: 400,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final texts = tester.widgetList<Text>(find.byType(Text));
      expect(texts.length, 2);
    });

    testWidgets('handles very long strings without crashing', (tester) async {
      final veryLongText = '超长歌词' * 100;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LyricsKaraokeLine(
            text: veryLongText,
            fontSize: 32,
            playedColor: Colors.amber,
            unplayedColor: Colors.white,
            progress: 0.8,
            availableWidth: 300,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('applies textOpacity to colors and shadows', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: LyricsKaraokeLine(
            text: 'Opacity Test',
            fontSize: 24,
            playedColor: Color(0xFFFFCC00),
            unplayedColor: Color(0xFFFFFFFF),
            progress: 0.5,
            availableWidth: 500,
            textOpacity: 0.5,
          ),
        ),
      );

      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      final baseText = texts[0];
      final highlightText = texts[1];

      // Base unplayed text opacity
      expect(baseText.style?.color?.a, closeTo(0.5, 0.01));
      // Highlight played text opacity
      expect(highlightText.style?.color?.a, closeTo(0.5, 0.01));
    });
  });
}
