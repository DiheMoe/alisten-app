import 'package:alisten/shared/ui/drop.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 右上角的按钮，菜单盖住它往下展开。
  const anchor = Rect.fromLTWH(300, 20, 40, 40);
  const card = Rect.fromLTWH(140, 20, 200, 120);
  const cardRadius = 16.0;

  DropFrame frameOf(Pour pour) =>
      dropFrameOf(pour, anchor: anchor, card: card, cardRadius: cardRadius);

  Matcher near(Offset point) => isA<Offset>()
      .having((p) => p.dx, 'dx', closeTo(point.dx, 0.5))
      .having((p) => p.dy, 'dy', closeTo(point.dy, 0.5));

  group('pouring out', () {
    test('starts as a small round body in the button, the button itself '
        'being the drop', () {
      final frame = frameOf(const PourOut(progress: 0, time: 0, squared: 0));
      expect(frame.body.center, near(anchor.center));
      expect(frame.body.width, closeTo(0.41 * 40, 0.01));
      expect(frame.body.height, closeTo(0.41 * 40, 0.01));
      expect(frame.drop, anchor);
      expect(frame.glyph, 1);
      expect(frame.solid, 0);
    });

    test('overshoots the card away from the button, as if poured', () {
      final frame = frameOf(
        const PourOut(progress: 0.7, time: 0.098, squared: 0.3),
      );
      final straight = Offset.lerp(anchor.center, card.center, 0.7)!;
      expect(frame.body.center.dy, greaterThan(straight.dy + 20));
    });

    test('settled, the body is the card and the drop has sunk into it', () {
      final frame = frameOf(const PourOut(progress: 1, time: 1, squared: 1));
      expect(frame.body.topLeft, near(card.topLeft));
      expect(frame.body.bottomRight, near(card.bottomRight));
      expect(frame.bodyRadius, closeTo(cardRadius, 0.01));
      expect(card.deflate(20).contains(frame.drop.center), isTrue);
      expect(frame.drop.width, closeTo(10, 0.01));
      expect(frame.rim, closeTo(1, 1e-6));
      expect(frame.glyph, 0);
    });
  });

  group('flowing back', () {
    test('starts from the card', () {
      final frame = frameOf(const PourBack(time: 0));
      expect(frame.body.topLeft, near(card.topLeft));
      expect(frame.body.bottomRight, near(card.bottomRight));
      expect(frame.glyph, closeTo(0.2, 0.001));
    });

    test('the drop rises past the button before it lands on it', () {
      final rising = frameOf(const PourBack(time: 0.176));
      expect(rising.drop.center.dy, lessThan(anchor.center.dy - 5));

      final landed = frameOf(const PourBack(time: returnSeconds));
      expect(landed.drop.topLeft, near(anchor.topLeft));
      expect(landed.drop.bottomRight, near(anchor.bottomRight));
      expect(landed.body.center, near(anchor.center));
      expect(landed.body.width, closeTo(0.41 * 40, 0.01));
    });

    test('the button shows through the drop as it lands, and the drop fades '
        'into it', () {
      final landed = frameOf(const PourBack(time: returnSeconds));
      expect(landed.glyph, 1);
      expect(landed.solid, 0);
      expect(landed.blend, 0);
    });

    test('the content blurs out within a tenth of a second', () {
      expect(const PourBack(time: 0).reveal, 1);
      expect(const PourBack(time: 0.1).reveal, 0);
      expect(const PourBack(time: 0.1).contentBlur, 8);
    });

    test('caught while still pouring out, it flows back from there', () {
      const opening = PourOut(progress: 0.3, time: 0.04, squared: 0);
      final from = frameOf(opening);
      final frame = frameOf(const PourBack(time: 0, from: opening));
      expect(frame.body.center, near(from.body.center));
      expect(frame.body.width, closeTo(from.body.width, 0.5));
      expect(frame.solid, from.solid);
    });
  });
}
