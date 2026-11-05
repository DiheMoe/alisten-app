import 'package:alisten/shared/ui/nudge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const icon = Key('icon');

  Widget nudge(Object? trigger, {bool disableAnimations = false}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: Nudge(
            trigger: trigger,
            child: const SizedBox.square(key: icon, dimension: 24),
          ),
        ),
      ),
    );
  }

  double at(WidgetTester tester) => tester.getTopLeft(find.byKey(icon)).dx;

  testWidgets('a new trigger pushes the child forward and springs back', (
    tester,
  ) async {
    await tester.pumpWidget(nudge(null));
    expect(at(tester), 0);

    await tester.pumpWidget(nudge('a'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(at(tester), greaterThan(0));

    await tester.pumpAndSettle();
    expect(at(tester), 0);
  });

  testWidgets('the same trigger stays still', (tester) async {
    await tester.pumpWidget(nudge('a'));

    await tester.pumpWidget(nudge('a'));
    await tester.pump(const Duration(milliseconds: 80));

    expect(at(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a trigger taken away stays still', (tester) async {
    await tester.pumpWidget(nudge('a'));

    await tester.pumpWidget(nudge(null));
    await tester.pump(const Duration(milliseconds: 80));

    expect(at(tester), 0);
  });

  testWidgets('removed animations stay still', (tester) async {
    await tester.pumpWidget(nudge(null, disableAnimations: true));

    await tester.pumpWidget(nudge('a', disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 80));

    expect(at(tester), 0);
  });
}
