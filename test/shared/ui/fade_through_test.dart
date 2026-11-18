import 'package:alisten/shared/theme/motion.dart';
import 'package:alisten/shared/ui/fade_through.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpSwitcher(WidgetTester tester, String shown) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: AnimatedSwitcher(
            duration: AlistenMotion.fadeThrough,
            transitionBuilder: fadeThrough,
            child: GestureDetector(
              key: ValueKey(shown),
              onTap: () {},
              child: SizedBox(width: 100, height: 40, child: Text(shown)),
            ),
          ),
        ),
      ),
    );
  }

  double opacityOf(WidgetTester tester, String text) => tester
      .widget<Opacity>(
        find
            .ancestor(of: find.text(text), matching: find.byType(Opacity))
            .first,
      )
      .opacity;

  double scaleOf(WidgetTester tester, String text) =>
      tester.getRect(find.text(text)).width /
      tester.getSize(find.text(text)).width;

  testWidgets('the old content fades out first, then the new one grows in '
      'from 0.92', (tester) async {
    await pumpSwitcher(tester, '加载中');
    await pumpSwitcher(tester, '歌单');

    await tester.pump(const Duration(milliseconds: 45));
    expect(opacityOf(tester, '加载中'), inExclusiveRange(0, 1));
    expect(opacityOf(tester, '歌单'), 0);
    expect(scaleOf(tester, '歌单'), closeTo(0.92, 1e-6));

    await tester.pump(const Duration(milliseconds: 60));
    expect(opacityOf(tester, '加载中'), 0);

    await tester.pump(const Duration(milliseconds: 100));
    expect(opacityOf(tester, '歌单'), inExclusiveRange(0, 1));
    expect(scaleOf(tester, '歌单'), inExclusiveRange(0.92, 1));

    await tester.pumpAndSettle();
    expect(find.text('加载中'), findsNothing);
    expect(opacityOf(tester, '歌单'), 1);
    expect(scaleOf(tester, '歌单'), 1);
  });

  testWidgets('the content leaving takes no taps and is not read out', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSwitcher(tester, '重试');
    await pumpSwitcher(tester, '歌单');
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      find.ancestor(
        of: find.text('重试'),
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsOneWidget,
    );
    expect(find.semantics.byLabel('重试'), findsNothing);
    expect(find.semantics.byLabel('歌单'), findsOne);
    await tester.pumpAndSettle();
    semantics.dispose();
  });
}
