import 'package:alisten/shared/ui/zoom_frame.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _origin = Rect.fromLTWH(700, 20, 40, 40);
const _content = Key('content');

Future<void> _pump(
  WidgetTester tester, {
  required double growth,
  Rect? from = _origin,
  Offset offset = Offset.zero,
  double scale = 1,
  bool clipAtRest = false,
}) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ZoomFrame(
        growth: growth,
        from: from,
        riseBy: 600,
        fromRadius: 20,
        toRadius: const BorderRadius.all(Radius.circular(30)),
        clipAtRest: clipAtRest,
        offset: offset,
        scale: scale,
        fill: const Color(0xFFFFFFFF),
        child: const SizedBox.expand(key: _content),
      ),
    ),
  );
}

Rect _shape(WidgetTester tester) {
  final frame = tester.renderObject<RenderZoomFrame>(find.byType(ZoomFrame));
  return MatrixUtils.transformRect(frame.getTransformTo(null), frame.shape);
}

void main() {
  testWidgets('at 0 the frame sits on its origin, at 1 on itself, unclipped', (
    tester,
  ) async {
    await _pump(tester, growth: 0);
    expect(_shape(tester), _origin);
    expect(
      tester.renderObject<RenderZoomFrame>(find.byType(ZoomFrame)).radius,
      const BorderRadius.all(Radius.circular(20)),
    );

    await _pump(tester, growth: 1);
    expect(_shape(tester), const Offset(0, 0) & const Size(800, 600));
    expect(find.byType(ZoomFrame), isNot(paints..clipRRect()));
  });

  testWidgets('a frame that keeps its corners at rest is clipped at rest', (
    tester,
  ) async {
    await _pump(tester, growth: 1, clipAtRest: true);

    expect(find.byType(ZoomFrame), paints..clipRRect());
  });

  testWidgets('without an origin it rises from below', (tester) async {
    await _pump(tester, growth: 0, from: null);

    expect(_shape(tester), const Offset(0, 600) & const Size(800, 600));
  });

  testWidgets('a dragged frame ends where the drag put it', (tester) async {
    await _pump(tester, growth: 1, offset: const Offset(100, 0), scale: 0.85);

    final shape = _shape(tester);
    expect(shape.width, closeTo(680, 1e-6));
    expect(shape.center.dx, closeTo(500, 1e-6));
  });

  testWidgets('the content covers the frame, anchored at its top centre', (
    tester,
  ) async {
    await _pump(tester, growth: 0.5);

    final shape = _shape(tester);
    final content = tester.getRect(find.byKey(_content));
    expect(content.width, greaterThanOrEqualTo(shape.width - 1e-6));
    expect(content.height, greaterThanOrEqualTo(shape.height - 1e-6));
    expect(content.top, closeTo(shape.top, 1e-6));
    expect(content.center.dx, closeTo(shape.center.dx, 1e-6));
  });
}
