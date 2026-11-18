import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int presses;

  Future<void> pumpList(WidgetTester tester) async {
    presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        // 列表中的点按要与滚动竞争，手指抬起后才能确认是点按。
        home: ListView(
          children: [
            Pressable(
              onPressed: () => presses++,
              child: const SizedBox(height: 60),
            ),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    );
  }

  // 按下的墨迹画在前景里，透明度随按下的程度变化。
  double ink(WidgetTester tester) => tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((box) => (box.decoration as BoxDecoration).color?.a ?? 0)
      .fold(0, math.max);

  testWidgets('a quick tap in a list still shows as pressed for a moment', (
    tester,
  ) async {
    await pumpList(tester);

    await tester.tap(find.byType(Pressable));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(presses, 1);
    expect(ink(tester), greaterThan(0));

    await tester.pumpAndSettle();
    expect(ink(tester), 0);
  });

  testWidgets('a press lets go once the finger scrolls the list', (
    tester,
  ) async {
    await pumpList(tester);

    final finger = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    // 先等到按下生效，墨迹从下一帧开始淡入。
    await tester.pump(kPressTimeout + const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 80));
    final pressed = ink(tester);
    expect(pressed, greaterThan(0));

    await finger.moveBy(const Offset(0, -kTouchSlop * 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ink(tester), lessThan(pressed));
    await finger.up();
    await tester.pumpAndSettle();
    expect(ink(tester), 0);
    expect(presses, 0);
  });

  testWidgets('a press tints instead of shrinking: the ink rises over 200 ms '
      'to a tenth', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: Center(
          child: Pressable(
            onPressed: () {},
            child: const SizedBox(width: 100, height: 60),
          ),
        ),
      ),
    );

    final finger = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ink(tester), closeTo(0.05, 0.01));
    await tester.pump(const Duration(milliseconds: 150));
    expect(ink(tester), closeTo(0.1, 1e-6));
    expect(
      find.descendant(
        of: find.byType(Pressable),
        matching: find.byWidgetPredicate(
          (widget) => widget is AnimatedScale || widget is ScaleTransition,
        ),
      ),
      findsNothing,
    );

    await finger.up();
    await tester.pumpAndSettle();
    expect(ink(tester), 0);
  });

  testWidgets('a given focus node takes the focus and the activation', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: Pressable(
            focusNode: node,
            onPressed: () => pressed++,
            child: const SizedBox.square(dimension: 48),
          ),
        ),
      ),
    );

    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(node.hasFocus, isTrue);
    expect(pressed, 1);
  });
}
