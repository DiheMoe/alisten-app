import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/morph_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpMenu(WidgetTester tester, Alignment at) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.light)),
        home: Scaffold(
          body: Align(
            alignment: at,
            child: ActionMenuButton(
              semanticLabel: '更多',
              entries: [
                ActionMenuEntry(
                  icon: AlistenIcons.copy,
                  label: '复制',
                  onSelected: () {},
                ),
                ActionMenuEntry(
                  icon: AlistenIcons.trash,
                  label: '删除',
                  danger: true,
                  onSelected: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Rect trigger(WidgetTester tester) =>
      tester.getRect(find.byIcon(AlistenIcons.dotsThreeBold));

  RenderMorphPanel panel(WidgetTester tester) =>
      tester.renderObject<RenderMorphPanel>(find.byType(MorphPanel));

  Rect shape(WidgetTester tester) {
    final panel = tester.renderObject<RenderMorphPanel>(
      find.byType(MorphPanel),
    );
    return MatrixUtils.transformRect(panel.getTransformTo(null), panel.shape);
  }

  // 面板坐标里的点换到屏幕上。
  Offset local(WidgetTester tester, Offset point) =>
      MatrixUtils.transformPoint(panel(tester).getTransformTo(null), point);

  Rect button(WidgetTester tester) => tester.getRect(
    find.ancestor(
      of: find.byIcon(AlistenIcons.dotsThreeBold),
      matching: find.byType(IconCircleButton),
    ),
  );

  testWidgets('opens over its button, corner on corner, so the button '
      'itself becomes the menu', (tester) async {
    await pumpMenu(tester, const Alignment(0.9, -0.8));
    final from = button(tester);

    await tester.tap(find.byIcon(AlistenIcons.dotsThreeBold));
    await tester.pumpAndSettle();

    final menu = shape(tester);
    expect(menu.topRight.dx, closeTo(from.topRight.dx, 1));
    expect(menu.topRight.dy, closeTo(from.topRight.dy, 1));
    expect(menu.contains(trigger(tester).center), isTrue);
  });

  testWidgets('near the bottom it opens upward over its button, bottom corner '
      'on bottom corner', (tester) async {
    await pumpMenu(tester, const Alignment(0.9, 0.8));
    final from = button(tester);

    await tester.tap(find.byIcon(AlistenIcons.dotsThreeBold));
    await tester.pumpAndSettle();

    final menu = shape(tester);
    expect(menu.bottomRight.dx, closeTo(from.bottomRight.dx, 1));
    expect(menu.bottomRight.dy, closeTo(from.bottomRight.dy, 1));
  });

  Iterable<Opacity> hiding(WidgetTester tester) => tester
      .widgetList<Opacity>(
        find.ancestor(
          of: find.byIcon(AlistenIcons.dotsThreeBold),
          matching: find.byType(Opacity),
        ),
      )
      .where((opacity) => opacity.opacity == 0);

  testWidgets('pours out of its button: the button becomes a drop that sinks '
      'into the menu, and flows back into the button on close', (tester) async {
    await pumpMenu(tester, const Alignment(0.9, -0.8));
    final from = button(tester);

    await tester.tap(find.byIcon(AlistenIcons.dotsThreeBold));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 8));
    var frame = panel(tester).dropFrame!;
    expect(frame.drop.width, greaterThan(from.width * 0.8));
    expect(
      local(tester, frame.drop.center),
      isA<Offset>().having(
        (p) => (p - from.center).distance,
        'from the button',
        lessThan(8),
      ),
    );
    expect(hiding(tester), isNotEmpty, reason: 'the drop stands in for it');

    await tester.pumpAndSettle();
    expect(panel(tester).dropFrame, isNull);

    await tester.tapAt(const Offset(20, 580));
    await tester.pump();
    var rose = false;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      if (find.byType(MorphPanel).evaluate().isEmpty) break;
      frame = panel(tester).dropFrame!;
      rose |= local(tester, frame.drop.center).dy < from.center.dy - 3;
    }
    expect(rose, isTrue, reason: 'it rises past the button, then lands');
    await tester.pumpAndSettle();
    expect(find.byType(MorphPanel), findsNothing);
    expect(hiding(tester), isEmpty);
  });
}
