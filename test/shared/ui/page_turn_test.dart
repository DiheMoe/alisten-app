import 'package:alisten/shared/theme/motion.dart';
import 'package:alisten/shared/ui/page_turn.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const out = Duration(milliseconds: 90);
  const into = Duration(milliseconds: 210);
  // 动画在时间超过时长的那一帧才结束。
  const tick = Duration(milliseconds: 1);

  Widget turn(
    int page, {
    String? text,
    VoidCallback? onTurned,
    VoidCallback? onTap,
    bool reduced = false,
    TextDirection direction = TextDirection.ltr,
  }) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Directionality(
        textDirection: direction,
        child: Align(
          alignment: Alignment.topLeft,
          child: PageTurn(
            page: page,
            onTurned: onTurned,
            child: GestureDetector(
              onTap: onTap,
              child: Text(text ?? 'page $page'),
            ),
          ),
        ),
      ),
    );
  }

  double opacityOf(WidgetTester tester, String text) => tester
      .widget<Opacity>(
        find.ancestor(of: find.text(text), matching: find.byType(Opacity)),
      )
      .opacity;

  double shiftOf(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dx;

  test('the turn lasts as long as the fade through it is built on', () {
    expect(out + into, AlistenMotion.fadeThrough);
  });

  testWidgets('a later page: the old one leaves toward the start, then the new '
      'one comes in from the end, and the two never show together', (
    tester,
  ) async {
    var turned = 0;
    await tester.pumpWidget(turn(1));
    expect(opacityOf(tester, 'page 1'), 1);
    expect(shiftOf(tester, 'page 1'), 0);

    await tester.pumpWidget(turn(2, onTurned: () => turned++));
    expect(find.text('page 2'), findsNothing);

    await tester.pump();
    await tester.pump(out ~/ 2);
    expect(opacityOf(tester, 'page 1'), inExclusiveRange(0, 1));
    expect(shiftOf(tester, 'page 1'), lessThan(0));
    expect(find.text('page 2'), findsNothing);
    expect(turned, 0);

    await tester.pump(out ~/ 2 + tick);
    await tester.pump();
    expect(find.text('page 1'), findsNothing);
    expect(turned, 1);
    expect(opacityOf(tester, 'page 2'), 0);
    expect(shiftOf(tester, 'page 2'), AlistenMotion.pageTurnShift);

    await tester.pump(into ~/ 2);
    expect(opacityOf(tester, 'page 2'), inExclusiveRange(0, 1));
    expect(
      shiftOf(tester, 'page 2'),
      inExclusiveRange(0, AlistenMotion.pageTurnShift),
    );

    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'page 2'), 1);
    expect(shiftOf(tester, 'page 2'), 0);
    expect(turned, 1);
  });

  testWidgets('an earlier page moves the other way', (tester) async {
    await tester.pumpWidget(turn(3));
    await tester.pumpWidget(turn(2));

    await tester.pump();
    await tester.pump(out ~/ 2);
    expect(shiftOf(tester, 'page 3'), greaterThan(0));

    await tester.pump(out ~/ 2 + tick);
    await tester.pump();
    expect(shiftOf(tester, 'page 2'), -AlistenMotion.pageTurnShift);
  });

  testWidgets('right to left, a later page leaves toward the right', (
    tester,
  ) async {
    await tester.pumpWidget(turn(1, direction: TextDirection.rtl));
    final rest = shiftOf(tester, 'page 1');
    await tester.pumpWidget(turn(2, direction: TextDirection.rtl));

    await tester.pump();
    await tester.pump(out ~/ 2);
    expect(shiftOf(tester, 'page 1'), greaterThan(rest));
  });

  testWidgets('with reduced motion the page is replaced at once', (
    tester,
  ) async {
    var turned = 0;
    await tester.pumpWidget(turn(1, reduced: true));
    await tester.pumpWidget(turn(2, reduced: true, onTurned: () => turned++));
    await tester.pump();

    expect(find.text('page 1'), findsNothing);
    expect(opacityOf(tester, 'page 2'), 1);
    expect(shiftOf(tester, 'page 2'), 0);
    expect(turned, 1);
  });

  testWidgets('what changes on the same page changes in place', (tester) async {
    var turned = 0;
    await tester.pumpWidget(turn(1, text: 'before'));
    await tester.pumpWidget(turn(1, text: 'after', onTurned: () => turned++));

    expect(find.text('before'), findsNothing);
    expect(opacityOf(tester, 'after'), 1);
    expect(turned, 0);
  });

  testWidgets('a page asked for while another is leaving is the one that '
      'comes in', (tester) async {
    var turned = 0;
    await tester.pumpWidget(turn(1));
    await tester.pumpWidget(turn(2, onTurned: () => turned++));
    await tester.pump();
    await tester.pump(out ~/ 3);
    await tester.pumpWidget(turn(3, onTurned: () => turned++));
    await tester.pumpAndSettle();

    expect(find.text('page 2'), findsNothing);
    expect(opacityOf(tester, 'page 3'), 1);
    expect(turned, 1);
  });

  testWidgets('a page on its way out takes no taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(turn(1, onTap: () => taps++));
    await tester.tap(find.text('page 1'));
    expect(taps, 1);

    await tester.pumpWidget(turn(2, onTap: () => taps++));
    await tester.pump();
    await tester.pump(out ~/ 2);
    await tester.tap(find.text('page 1'), warnIfMissed: false);
    expect(taps, 1);

    await tester.pumpAndSettle();
    await tester.tap(find.text('page 2'));
    expect(taps, 2);
  });
}
