import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/morph_panel.dart';
import 'package:alisten/shared/ui/pressable.dart';
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

  group('a dangerous entry after the others', () {
    Future<(Rect, Rect)> rows(WidgetTester tester) async {
      await pumpMenu(tester, const Alignment(0.9, -0.8));
      await tester.tap(find.byIcon(AlistenIcons.dotsThreeBold));
      await tester.pumpAndSettle();
      Rect row(String label) => tester.getRect(
        find.ancestor(of: find.text(label), matching: find.byType(Pressable)),
      );
      return (row('复制'), row('删除'));
    }

    testWidgets('on a phone follows them directly, its icon as far from the '
        'words as before', (tester) async {
      final (copy, delete) = await rows(tester);
      expect(delete.top, copy.bottom);
      expect(
        tester.getRect(find.text('复制')).left -
            tester.getRect(find.byIcon(AlistenIcons.copy)).right,
        AlistenSpacing.sm,
      );
    });

    testWidgets('in a desktop window is set apart by a rule', (tester) async {
      final (copy, delete) = await rows(tester);
      expect(delete.top, greaterThan(copy.bottom));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

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

  testWidgets(
    'below mode blooms from the anchor edge below the trigger without covering '
    'it or drawing a circular drop over it',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.light)),
          home: Scaffold(
            body: Align(
              alignment: const Alignment(-0.8, -0.8),
              child: ActionMenuButton(
                semanticLabel: '房间操作',
                below: true,
                trigger: (open, toggle) => GestureDetector(
                  onTap: toggle,
                  child: const SizedBox(
                    width: 140,
                    height: 32,
                    child: Center(child: Text('房间名')),
                  ),
                ),
                entries: [
                  ActionMenuEntry(
                    icon: AlistenIcons.copy,
                    label: '复制',
                    onSelected: () {},
                  ),
                  ActionMenuEntry(
                    icon: AlistenIcons.trash,
                    label: '退出',
                    danger: true,
                    onSelected: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final triggerBox = tester.getRect(find.byType(ActionMenuButton));

      await tester.tap(find.text('房间名'));
      await tester.pump();
      // 从锚点零尺寸开始完整展开，不覆盖标题，也不画圆形液滴。
      expect(panel(tester).dropFrame, isNull);
      expect(shape(tester).width, lessThan(1));
      expect(shape(tester).top, greaterThanOrEqualTo(triggerBox.bottom - 1));

      await tester.pumpAndSettle();
      final menu = shape(tester);
      expect(menu.top, greaterThan(triggerBox.bottom));
      expect(menu.left, closeTo(triggerBox.left, 1));

      // 收回途中外框始终保持在标题底缘以下，不盖到标题文字上。
      await tester.tapAt(const Offset(500, 500));
      await tester.pump();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 24));
        if (find.byType(MorphPanel).evaluate().isEmpty) break;
        expect(shape(tester).top, greaterThanOrEqualTo(triggerBox.bottom - 1));
      }
      await tester.pumpAndSettle();
      expect(find.byType(MorphPanel), findsNothing);
    },
  );
}
