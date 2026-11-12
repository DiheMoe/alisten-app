import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  bool still = false,
  String? semanticLabel,
}) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: Center(
          child: BusyIndicator(
            size: 16,
            color: const Color(0xFFFFFFFF),
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a faint full ring carries the arc, so a small one still reads '
      'as a spinner', (tester) async {
    await _pump(tester);

    expect(
      find.byType(BusyIndicator),
      paints
        ..circle(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.2),
          style: PaintingStyle.stroke,
          strokeWidth: 2.5,
        )
        ..arc(
          color: const Color(0xFFFFFFFF),
          style: PaintingStyle.stroke,
          strokeWidth: 2.5,
          strokeCap: StrokeCap.round,
        ),
    );
  });

  testWidgets('it turns, and stands still once animations are removed', (
    tester,
  ) async {
    await _pump(tester);
    expect(tester.hasRunningAnimations, isTrue);

    await _pump(tester, still: true);
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('it says nothing unless told what is in progress', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(find.semantics.byLabel('加载中'), findsNothing);

    await _pump(tester, semanticLabel: '加载中');
    expect(find.semantics.byLabel('加载中'), findsOne);
    semantics.dispose();
  });
}
