import 'dart:math' as math;

import 'package:alisten/shared/ui/edge_track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const edge = EdgeTrack(width: 300, radius: 20, inset: 2.5);
  const arc = 20 - 2.5;

  Matcher near(Offset point) => isA<Offset>()
      .having((p) => p.dx, 'dx', closeTo(point.dx, 1e-6))
      .having((p) => p.dy, 'dy', closeTo(point.dy, 1e-6));

  test('starts on the left side where the top corner begins, runs along the '
      'top edge and ends on the right side', () {
    expect(edge.pointAt(0), near(const Offset(2.5, 20)));
    expect(edge.pointAt(edge.length / 2), near(const Offset(150, 2.5)));
    expect(edge.pointAt(edge.length), near(const Offset(300 - 2.5, 20)));
  });

  test('counts the corners by their arc, so it moves as fast round them as '
      'along the top', () {
    expect(edge.length, closeTo(2 * (math.pi / 2) * arc + (300 - 40), 1e-9));
    // 走完一个弯正好到上边的起点。
    expect(edge.pointAt(math.pi / 2 * arc), near(const Offset(20, 2.5)));
    // 弯到一半在圆角的 45° 处。
    final halfway = edge.pointAt(math.pi / 4 * arc);
    expect(
      halfway,
      near(
        Offset(
          20 - arc * math.cos(math.pi / 4),
          20 - arc * math.sin(math.pi / 4),
        ),
      ),
    );
  });

  test('a shorter sweep starts higher up the corner', () {
    const capsule = EdgeTrack(
      width: 300,
      radius: 20,
      inset: 2.5,
      sweep: math.pi / 3,
    );
    expect(capsule.pointAt(0).dy, lessThan(20));
    expect(capsule.pointAt(0).dx, greaterThan(2.5));
  });

  test('the drawn path and the part up to a point follow the same line', () {
    final whole = edge.path.computeMetrics().single;
    expect(whole.length, closeTo(edge.length, 0.5));
    final part = edge.upTo(edge.length / 2).computeMetrics().single;
    expect(part.length, closeTo(edge.length / 2, 0.5));
    final end = part.getTangentForOffset(part.length)!.position;
    expect(end, isA<Offset>().having((p) => p.dx, 'dx', closeTo(150, 0.5)));
  });
}
