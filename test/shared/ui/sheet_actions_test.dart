import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, {double width = 480}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.light)),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SheetActions(
                children: [
                  PillButton(label: '退出房间', large: true, onPressed: () {}),
                  PillButton(
                    label: '稍后',
                    style: PillButtonStyle.secondary,
                    onPressed: () {},
                  ),
                  PillButton(
                    label: '取消',
                    style: PillButtonStyle.ghost,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect button(WidgetTester tester, String label) =>
      tester.getRect(find.widgetWithText(PillButton, label));

  testWidgets('on a phone the actions are stacked across the whole width, '
      'the main one on top', (tester) async {
    await pump(tester);
    final main = button(tester, '退出房间');
    final later = button(tester, '稍后');
    final cancel = button(tester, '取消');
    expect(main.width, 480);
    expect(later.width, 480);
    expect(cancel.width, 480);
    expect(main.bottom, lessThan(later.top));
    expect(later.bottom, lessThan(cancel.top));
    expect(main.height, greaterThan(cancel.height));
  });

  testWidgets(
    'in a desktop window the actions sit side by side at the far end, '
    'the main one last',
    (tester) async {
      await pump(tester);
      final area = tester.getRect(find.byType(SheetActions));
      final main = button(tester, '退出房间');
      final later = button(tester, '稍后');
      final cancel = button(tester, '取消');
      expect(main.right, area.right);
      expect(later.right, lessThan(main.left));
      expect(cancel.right, lessThan(later.left));
      expect(cancel.left, greaterThan(area.left));
      expect(main.top, cancel.top);
      expect(main.height, cancel.height);
      expect(main.height, later.height);
      // 两个字的按钮也不会窄成一小块。
      expect(cancel.width, greaterThanOrEqualTo(88));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'a desktop window too narrow for one row stacks them, the main one on top',
    (tester) async {
      await pump(tester, width: 200);
      final main = button(tester, '退出房间');
      final cancel = button(tester, '取消');
      expect(main.bottom, lessThanOrEqualTo(button(tester, '稍后').top));
      expect(button(tester, '稍后').bottom, lessThanOrEqualTo(cancel.top));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
