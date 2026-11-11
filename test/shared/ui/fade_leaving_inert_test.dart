import 'package:alisten/shared/ui/fade_leaving_inert.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('what fades out can no longer be tapped or read; what fades '
      'in can', (tester) async {
    final semantics = tester.ensureSemantics();
    final taps = <String>[];
    Widget button(String label, double width) => Semantics(
      key: ValueKey(label),
      button: true,
      label: label,
      onTap: () => taps.add(label),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => taps.add(label),
        child: SizedBox(width: width, height: 40),
      ),
    );
    Widget page(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: fadeLeavingInert,
          child: child,
        ),
      ),
    );

    await tester.pumpWidget(page(button('旧的', 200)));
    final edge =
        tester.getTopLeft(find.byKey(const ValueKey('旧的'))) +
        const Offset(5, 5);
    await tester.tapAt(edge);
    expect(taps, ['旧的']);

    await tester.pumpWidget(page(button('新的', 20)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('旧的')), findsOneWidget);
    await tester.tapAt(edge);
    await tester.tap(find.byKey(const ValueKey('新的')));

    expect(taps, ['旧的', '新的']);
    expect(find.semantics.byLabel('旧的'), findsNothing);
    expect(find.semantics.byLabel('新的'), findsOne);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('旧的')), findsNothing);
    semantics.dispose();
  });
}
