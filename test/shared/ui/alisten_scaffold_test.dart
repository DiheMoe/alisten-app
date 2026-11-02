import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _screen = Size(300, 600);
const _bar = 60.0;
const _nav = 20.0;
const _barTotal = _bar + _nav;

final _body = GlobalKey();

Finder get _bottomBar => find.bySemanticsLabel('底栏');

/// 与系统一致：被键盘遮住的安全区不再计入 `padding`。
Widget _page({
  required double keyboard,
  bool bar = true,
  bool resize = true,
  VoidCallback? onTap,
  FocusNode? bodyFocus,
  FocusNode? barFocus,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: _screen,
      viewInsets: EdgeInsets.only(bottom: keyboard),
      viewPadding: const EdgeInsets.only(bottom: _nav),
      padding: EdgeInsets.only(bottom: math.max(0, _nav - keyboard)),
    ),
    child: MaterialApp(
      theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
      home: AlistenScaffold(
        resizeToAvoidBottomInset: resize,
        body: Focus(
          focusNode: bodyFocus,
          child: SizedBox.expand(key: _body),
        ),
        bottomBar: bar
            ? Focus(
                focusNode: barFocus,
                child: Semantics(
                  label: '底栏',
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                    child: const SizedBox(height: _bar, width: double.infinity),
                  ),
                ),
              )
            : null,
      ),
    ),
  );
}

void _onScreen(WidgetTester tester) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _screen;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the bottom bar stays on the bottom edge as a keyboard rises '
      'over it, and the body ends above whichever is higher', (tester) async {
    _onScreen(tester);
    const barRect = Rect.fromLTWH(0, 600 - _barTotal, 300, _bar);
    final rising = [for (var inset = 0.0; inset <= 300; inset += 10) inset];
    final steps = [...rising, ...rising.reversed.skip(1)];

    double? last;
    for (final (index, keyboard) in steps.indexed) {
      await tester.pumpWidget(_page(keyboard: keyboard));

      final reason = 'keyboard $keyboard';
      final bottom = tester.getRect(find.byKey(_body)).bottom;
      expect(
        bottom,
        moreOrLessEquals(600 - math.max(keyboard, _barTotal)),
        reason: reason,
      );
      expect(tester.getRect(_bottomBar), barRect, reason: reason);
      // 键盘升起时正文底边只升不降，收起时只降不升。
      if (last != null) {
        expect(
          bottom,
          index < rising.length
              ? lessThanOrEqualTo(last)
              : greaterThanOrEqualTo(last),
          reason: reason,
        );
      }
      last = bottom;
    }
  });

  testWidgets('a bottom bar wholly under the keyboard takes no taps and '
      'leaves the semantics tree', (tester) async {
    _onScreen(tester);
    final semantics = tester.ensureSemantics();
    var taps = 0;

    for (final (keyboard, covered) in [
      (0.0, false),
      (_barTotal - 1, false),
      (_barTotal, true),
      (300.0, true),
      (0.0, false),
    ]) {
      await tester.pumpWidget(_page(keyboard: keyboard, onTap: () => taps++));
      final reason = 'keyboard $keyboard';
      expect(
        find.semantics.byLabel('底栏'),
        covered ? findsNothing : findsOne,
        reason: reason,
      );

      // 点在底栏顶边：键盘差 1 px 盖满底栏时，这里仍露在键盘之上。
      final before = taps;
      await tester.tapAt(const Offset(150, 600 - _barTotal + 0.5));
      expect(taps, before + (covered ? 0 : 1), reason: reason);
    }
    semantics.dispose();
  });

  testWidgets('a bottom bar wholly under the keyboard takes no focus, by Tab '
      'or when asked, and gives up the focus it had', (tester) async {
    _onScreen(tester);
    final body = FocusNode(debugLabel: 'body');
    final bar = FocusNode(debugLabel: 'bar');
    addTearDown(body.dispose);
    addTearDown(bar.dispose);
    Future<void> show(double keyboard) => tester.pumpWidget(
      _page(keyboard: keyboard, bodyFocus: body, barFocus: bar),
    );
    Future<void> focusBody() async {
      body.requestFocus();
      await tester.pump();
    }

    Future<void> tab() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    await show(0);
    await focusBody();
    await tab();
    expect(bar.hasPrimaryFocus, isTrue, reason: 'shown');

    await show(_barTotal);
    await tester.pump();
    expect(bar.hasFocus, isFalse, reason: 'covered while it had the focus');
    await focusBody();
    for (var press = 0; press < 3; press++) {
      await tab();
      expect(bar.hasFocus, isFalse, reason: 'Tab $press while covered');
    }
    bar.requestFocus();
    await tester.pump();
    expect(bar.hasFocus, isFalse, reason: 'asked while covered');

    await show(_barTotal - 1);
    await focusBody();
    await tab();
    expect(bar.hasPrimaryFocus, isTrue, reason: 'partly shown again');
  });

  testWidgets('without a bottom bar the body ends at the keyboard, unless it '
      'is asked not to make room for it', (tester) async {
    _onScreen(tester);
    await tester.pumpWidget(_page(keyboard: 100, bar: false));
    expect(tester.getRect(find.byKey(_body)).bottom, 500);

    await tester.pumpWidget(_page(keyboard: 100, bar: false, resize: false));
    expect(tester.getRect(find.byKey(_body)).bottom, 600);
  });
}
