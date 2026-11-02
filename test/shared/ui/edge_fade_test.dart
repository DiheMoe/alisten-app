import 'dart:ui' as ui;

import 'package:alisten/shared/ui/edge_fade.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _top = 20.0;
const _bottom = 30.0;
const _row = 50.0;
const _width = 40.0;

final _shot = GlobalKey();

Widget _list({
  double height = 300,
  ScrollController? scroll,
  bool still = false,
  bool rowBoundaries = false,
  Color behind = const Color(0x00000000),
}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _shot,
          child: Container(
            width: _width,
            height: height,
            color: behind,
            child: EdgeFade(
              top: _top,
              bottom: _bottom,
              child: ListView.builder(
                controller: scroll,
                addRepaintBoundaries: rowBoundaries,
                itemExtent: _row,
                itemCount: 40,
                itemBuilder: (_, index) => EdgeFadeItem(
                  key: ValueKey(index),
                  child: const RepaintBoundary(
                    child: ColoredBox(color: Color(0xFFFFFFFF)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

List<int> _offscreenRows(WidgetTester tester) {
  return [
    for (final row in find.byType(EdgeFadeItem).evaluate())
      if (row.renderObject!.debugLayer case final ShaderMaskLayer layer
          when layer.attached)
        ((row.widget.key! as ValueKey<int>).value),
  ]..sort();
}

const _green = 1;
const _alpha = 3;

// 可视区中线上自上而下每个像素的 [channel] 通道值，取值 0 到 255。
Future<List<int>> _down(WidgetTester tester, {int channel = _alpha}) async {
  final shot = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
  final values = await tester.runAsync(() async {
    final image = await shot.toImage();
    final width = image.width;
    final height = image.height;
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    return [
      for (var y = 0; y < height; y++)
        bytes!.getUint8((y * width + width ~/ 2) * 4 + channel),
    ];
  });
  return values!;
}

// 两条带内由透明线性过渡到不透明，两带之间完全不透明。
void _expectBands(List<int> alpha) {
  final height = alpha.length;
  for (var y = 0; y < _top; y++) {
    expect(alpha[y], closeTo((y + 0.5) / _top * 255, 12), reason: 'y $y');
  }
  for (var y = _top.toInt(); y < height - _bottom; y++) {
    expect(alpha[y], 255, reason: 'y $y');
  }
  for (var y = (height - _bottom).toInt(); y < height; y++) {
    expect(
      alpha[y],
      closeTo((height - y - 0.5) / _bottom * 255, 12),
      reason: 'y $y',
    );
  }
}

void main() {
  testWidgets('only rows reaching into a band are drawn offscreen, each on '
      'its own, and the bands follow the scrolling', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_list(scroll: scroll));

    // 第 0 行伸入上方的带，第 5 行伸入下方的带。
    expect(_offscreenRows(tester), [0, 5]);
    expect(tester.layers.whereType<ShaderMaskLayer>(), hasLength(2));

    scroll.jumpTo(25);
    await tester.pump();
    expect(_offscreenRows(tester), [0, 5, 6]);
    expect(tester.layers.whereType<ShaderMaskLayer>(), hasLength(3));

    scroll.jumpTo(_row);
    await tester.pump();
    expect(_offscreenRows(tester), [1, 6]);
    expect(tester.layers.whereType<ShaderMaskLayer>(), hasLength(2));
  });

  for (final still in [false, true]) {
    testWidgets('rows fade out across each band and are opaque between '
        'them${still ? ', with animations removed' : ''}', (tester) async {
      await tester.pumpWidget(_list(still: still));

      _expectBands(await _down(tester));
    });
  }

  testWidgets('what is behind the list shows through the bands, as it would '
      'through the rows themselves', (tester) async {
    await tester.pumpWidget(_list(behind: const Color(0xFFFF0000)));

    // 白行盖在红底上：不透明处为白，透明处露出红底，而不是连同红底一起抹掉。
    expect(await _down(tester), everyElement(255));
    _expectBands(await _down(tester, channel: _green));
  });

  testWidgets('the bands keep their height when the list gets shorter, as it '
      'does under a keyboard', (tester) async {
    await tester.pumpWidget(_list());
    await tester.pumpWidget(_list(height: 140));

    final alpha = await _down(tester);
    expect(alpha, hasLength(140));
    _expectBands(alpha);
  });

  testWidgets('a row under a repaint boundary of its list is refused: it '
      'would not be repainted as the list scrolls', (tester) async {
    // 只露出一行，因此只报告一次。
    await tester.pumpWidget(_list(height: _row, rowBoundaries: true));

    expect(tester.takeException(), isFlutterError);
  });

  test('a band cannot be negative', () {
    for (final (top, bottom) in [(-1.0, 0.0), (0.0, -1.0)]) {
      expect(
        () => EdgeFade(top: top, bottom: bottom, child: const SizedBox()),
        throwsAssertionError,
        reason: '$top, $bottom',
      );
    }
  });
}
