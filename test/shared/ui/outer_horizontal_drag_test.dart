import 'package:alisten/shared/ui/outer_horizontal_drag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pageWidth = 400.0;

/// 第一页是可上下滚动的可选择文字，外面包着 [OuterHorizontalDrag]（[wrapped]
/// 为 false 时不包）；第二页是一行字。
final class _Pages {
  _Pages(this.tester);

  final WidgetTester tester;
  final controller = PageController();
  final scroll = ScrollController();
  final wrapped = ValueNotifier(true);

  Future<void> show() async {
    tester.view
      ..physicalSize = const Size(_pageWidth, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    addTearDown(wrapped.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageView(
            controller: controller,
            children: [
              ValueListenableBuilder(
                valueListenable: wrapped,
                builder: (context, wrapped, child) =>
                    wrapped ? OuterHorizontalDrag(child: child!) : child!,
                child: ListView(
                  controller: scroll,
                  children: [
                    for (var line = 0; line < 30; line++)
                      SizedBox(
                        height: 60,
                        child: SelectionArea(child: Text('第 $line 行')),
                      ),
                  ],
                ),
              ),
              const Center(child: Text('第二页')),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('a sideways drag that starts on selectable text turns the '
      'outer page', (tester) async {
    final pages = _Pages(tester);
    await pages.show();

    await tester.drag(find.text('第 2 行'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(pages.controller.page, 1);
    expect(find.text('第二页'), findsOneWidget);
  }, variant: TargetPlatformVariant.mobile());

  testWidgets('a short quick flick on selectable text turns the outer page', (
    tester,
  ) async {
    final pages = _Pages(tester);
    await pages.show();

    await tester.fling(find.text('第 2 行'), const Offset(-80, 0), 1500);
    await tester.pumpAndSettle();

    expect(pages.controller.page, 1);
  });

  testWidgets('a drag up the text still scrolls it, and a long press still '
      'selects it', (tester) async {
    final pages = _Pages(tester);
    await pages.show();

    await tester.drag(find.text('第 4 行'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(pages.scroll.offset, greaterThan(100));
    expect(pages.controller.page, 0);

    await tester.longPress(find.text('第 6 行'));
    await tester.pumpAndSettle();
    expect(find.text('Select all'), findsOneWidget);
  });

  testWidgets(
    'removed while it drags the outer page, it lets the page settle',
    (tester) async {
      final pages = _Pages(tester);
      await pages.show();

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('第 2 行')),
      );
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();
      expect(pages.controller.page, greaterThan(0.2));

      pages.wrapped.value = false;
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final page = pages.controller.page!;
      expect(page, page.roundToDouble());
    },
  );

  testWidgets('without an outer horizontal scrollable it leaves the child '
      'alone', (tester) async {
    tester.view
      ..physicalSize = const Size(_pageWidth, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const child = Key('child');
    await tester.pumpWidget(
      const MaterialApp(
        home: OuterHorizontalDrag(
          // 只在收到紧约束时才占满，借此确认约束原样传给子组件。
          child: SizedBox.shrink(
            key: child,
            child: SelectionArea(child: Text('独自')),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(child)), const Size(_pageWidth, 600));

    await tester.drag(find.text('独自'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
