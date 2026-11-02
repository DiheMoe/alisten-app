import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

  double pressedScale(WidgetTester tester) => tester
      .widget<AnimatedScale>(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.byType(AnimatedScale),
        ),
      )
      .scale;

  testWidgets('a quick tap in a list still shows as pressed for a moment', (
    tester,
  ) async {
    await pumpList(tester);

    await tester.tap(find.byType(Pressable));
    await tester.pump();
    expect(presses, 1);
    expect(pressedScale(tester), lessThan(1));

    await tester.pump(AlistenDurations.press);
    await tester.pumpAndSettle();
    expect(pressedScale(tester), 1);
  });

  testWidgets('a press lets go once the finger scrolls the list', (
    tester,
  ) async {
    await pumpList(tester);

    final finger = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump(kPressTimeout + const Duration(milliseconds: 20));
    expect(pressedScale(tester), lessThan(1));

    await finger.moveBy(const Offset(0, -kTouchSlop * 2));
    await tester.pump();
    expect(pressedScale(tester), 1);
    await finger.up();
    await tester.pumpAndSettle();
    expect(presses, 0);
  });
}
