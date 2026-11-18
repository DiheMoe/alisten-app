import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/select_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<int>> pumpSelect(WidgetTester tester, {int selected = 20}) async {
    final chosen = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SelectMenuButton<int>(
              label: '最近搜索保留',
              selected: selected,
              options: const [
                SelectOption(value: 10, label: '10 条'),
                SelectOption(value: 20, label: '20 条'),
                SelectOption(value: 50, label: '50 条'),
              ],
              onChanged: chosen.add,
            ),
          ),
        ),
      ),
    );
    return chosen;
  }

  testWidgets('shows the current choice and reads its name and value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSelect(tester);

    expect(find.text('20 条'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('最近搜索保留')),
      isSemantics(
        label: '最近搜索保留',
        value: '20 条',
        isButton: true,
        hasExpandedState: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('opens a menu of every choice with the current one ticked, and '
      'a choice is reported and closes it', (tester) async {
    final chosen = await pumpSelect(tester);

    await tester.tap(find.text('20 条'));
    await tester.pumpAndSettle();
    expect(find.text('10 条'), findsOneWidget);
    expect(find.text('50 条'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: find.text('20 条').last,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Semantics &&
                        widget.properties.selected != null,
                  ),
                )
                .first,
          )
          .properties
          .selected,
      isTrue,
    );

    await tester.tap(find.text('50 条'));
    await tester.pumpAndSettle();
    expect(chosen, [50]);
    expect(find.text('10 条'), findsNothing);
  });

  testWidgets('pressing it leaves no grey behind the value', (tester) async {
    await pumpSelect(tester);

    final press = await tester.startGesture(
      tester.getCenter(find.text('20 条')),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final tinted = tester
        .widgetList<DecoratedBox>(
          find.ancestor(
            of: find.text('20 条').first,
            matching: find.byType(DecoratedBox),
          ),
        )
        .where((box) {
          final decoration = box.decoration;
          return decoration is BoxDecoration &&
              decoration.color != null &&
              decoration.color!.a > 0;
        });
    expect(tinted, isEmpty);
    await press.up();
    await tester.pumpAndSettle();
  });
}
