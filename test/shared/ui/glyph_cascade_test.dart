import 'package:alisten/shared/ui/glyph_cascade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('glyphShown', () {
    test('starts the characters one after another, left first', () {
      expect(glyphShown(0, 5, 0), 0);
      expect(glyphShown(0, 5, 0.05), greaterThan(glyphShown(1, 5, 0.05)));
      expect(glyphShown(1, 5, 0.05), greaterThan(glyphShown(4, 5, 0.05)));
      expect(glyphShown(4, 5, 0.05), 0);
    });

    test('settles every character of a long name in time', () {
      for (var index = 0; index < 40; index++) {
        expect(glyphShown(index, 40, glyphCascadeSeconds), 1);
      }
      expect(glyphShown(39, 40, 0.27), greaterThan(0));
    });
  });

  group('GlyphCascade', () {
    Future<RenderObject> show(WidgetTester tester, double elapsed) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: GlyphCascade(elapsed: elapsed, child: const Text('abcde')),
          ),
        ),
      );
      return tester.renderObject(find.byType(GlyphCascade));
    }

    testWidgets('draws nothing before it starts', (tester) async {
      expect(await show(tester, -0.1), paintsNothing);
      expect(await show(tester, 0), paintsNothing);
    });

    testWidgets('draws only the first character at first, each clipped to '
        'itself', (tester) async {
      final cascade = await show(tester, 0.01);
      expect(cascade, paintsExactlyCountTimes(#drawParagraph, 1));
      expect(cascade, paints..clipRect());
    });

    testWidgets('draws the characters in flight one by one and the settled '
        'ones together', (tester) async {
      expect(
        await show(tester, 0.1),
        paintsExactlyCountTimes(#drawParagraph, 5),
      );
      expect(
        await show(tester, 0.4),
        paintsExactlyCountTimes(#drawParagraph, 2),
      );
    });

    testWidgets('once settled draws the text as it is', (tester) async {
      final cascade = await show(tester, glyphCascadeSeconds);
      expect(cascade, paintsExactlyCountTimes(#drawParagraph, 1));
      expect(cascade, isNot(paints..clipRect()));
    });
  });
}
