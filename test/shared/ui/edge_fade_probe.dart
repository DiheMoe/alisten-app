import 'package:alisten/shared/ui/edge_fade.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// [view] 只在 [top]、[bottom] 为 true 的边缘逐行渐隐：没有把整个视图画进离屏
/// 缓冲的 `ShaderMask`；伸进渐隐带的可见行各自离屏绘制，其余行不离屏；每条带内
/// 至少有一行，确保内容确实到达这条边。
void expectFadedByRow(
  WidgetTester tester,
  Finder view, {
  required bool top,
  required bool bottom,
}) {
  expect(
    find.descendant(of: view, matching: find.byType(ShaderMask)),
    findsNothing,
  );
  final fadeFinder = find.descendant(of: view, matching: find.byType(EdgeFade));
  final fade = tester.widget<EdgeFade>(fadeFinder);
  expect(fade.top > 0, top, reason: 'top band ${fade.top}');
  expect(fade.bottom > 0, bottom, reason: 'bottom band ${fade.bottom}');
  final area = tester.getRect(fadeFinder);
  final topBand = area.top + fade.top;
  final bottomBand = area.bottom - fade.bottom;

  var inTop = 0;
  var inBottom = 0;
  for (final row
      in find
          .descendant(of: fadeFinder, matching: find.byType(EdgeFadeItem))
          .evaluate()) {
    final box = row.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (!rect.overlaps(area)) continue;
    final offscreen = switch (box.debugLayer) {
      final ShaderMaskLayer layer => layer.attached,
      _ => false,
    };
    final reachesTop = fade.top > 0 && rect.top < topBand;
    final reachesBottom = fade.bottom > 0 && rect.bottom > bottomBand;
    expect(offscreen, reachesTop || reachesBottom, reason: '$rect in $area');
    if (offscreen) {
      expect(rect.height, lessThan(area.height / 2), reason: 'one row');
    }
    if (reachesTop) inTop++;
    if (reachesBottom) inBottom++;
  }
  if (top) expect(inTop, greaterThan(0), reason: 'a row at the top');
  if (bottom) expect(inBottom, greaterThan(0), reason: 'a row at the bottom');
}
