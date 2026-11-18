import 'package:alisten/shared/theme/motion.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a page covers most of its way in a tenth of a second and settles '
      'within 0.45 s', () {
    final page = springTo(
      AlistenSprings.page,
      from: 0,
      to: 1,
      velocity: AlistenSprings.pageLaunch,
    );

    expect(page.x(0.1), greaterThan(0.7));
    expect(page.x(0.1), lessThan(0.85));
    expect(page.isDone(0.45), isTrue);
    expect(page.isDone(0.2), isFalse);
  });

  test('springs end exactly where they head and stop', () {
    final sheet = springTo(AlistenSprings.sheet, from: 1, to: 0, velocity: -2);
    var t = 0.0;
    while (!sheet.isDone(t)) {
      t += 1 / 120;
      expect(t, lessThan(2));
    }
    expect(sheet.x(t), closeTo(0, 1e-3));
  });

  test('a spring curve starts at 0, ends at 1 and never goes back', () {
    final curve = SpringCurve(AlistenSprings.page, seconds: 0.3);

    expect(curve.transform(0), 0);
    expect(curve.transform(1), 1);
    var last = 0.0;
    for (var t = 0.0; t <= 1; t += 0.01) {
      final value = curve.transform(t);
      expect(value, greaterThanOrEqualTo(last));
      last = value;
    }
  });

  test('the menu springs overshoot a little, the page and sheet do not', () {
    double peak(SpringDescription spring) {
      final s = springTo(spring, from: 0, to: 1);
      var top = 0.0;
      for (var t = 0.0; t < 1.5; t += 1 / 240) {
        if (s.x(t) > top) top = s.x(t);
      }
      return top;
    }

    expect(peak(AlistenSprings.menuOpen), greaterThan(1.0));
    expect(peak(AlistenSprings.menuClose), lessThanOrEqualTo(1.0 + 1e-6));
    expect(peak(AlistenSprings.page), lessThanOrEqualTo(1.0 + 1e-6));
    expect(peak(AlistenSprings.sheet), lessThanOrEqualTo(1.0 + 1e-6));
  });

  test('a closing menu is half way back at 0.09 s and nearly in its '
      'trigger after 0.3 s', () {
    final close = springTo(AlistenSprings.menuClose, from: 1, to: 0);

    expect(close.x(0.09), closeTo(0.53, 0.06));
    expect(close.x(0.14), closeTo(0.26, 0.06));
    expect(close.x(0.3), lessThan(0.05));
  });
}
