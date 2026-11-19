import 'dart:async';

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/shared_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a text moving to another page cross-fades from its own look to '
      'the other one, each drawn as laid out and scaled into the flying box, '
      'without the overlay\'s fallback style, and moves back the same way', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SharedText(
              tag: 'facts',
              child: Text('7 首 · 昨天 10:30', style: TextStyle(fontSize: 13)),
            ),
          ),
        ),
      ),
    );
    final from = tester.getRect(find.text('7 首 · 昨天 10:30'));

    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            body: Center(
              child: SharedText(
                tag: 'facts',
                child: Text('7 首，更新于昨天 10:30', style: TextStyle(fontSize: 20)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final leaving = find.text('7 首 · 昨天 10:30');
    final arriving = find.text('7 首，更新于昨天 10:30');
    double opacity(Finder text) => tester
        .widgetList<FadeTransition>(
          find.ancestor(of: text, matching: find.byType(FadeTransition)),
        )
        .first
        .opacity
        .value;
    // 起点那份留在原处的不画；飞的那两份各在一层。
    final leavingFlight = leaving.last;
    final arrivingFlight = arriving.first;
    expect(opacity(leavingFlight), inExclusiveRange(0, 1.01));
    expect(opacity(arrivingFlight), inExclusiveRange(0, 1));
    // 外框沿直线从一头变到另一头，一行字在半路不会被压扁。
    final flying = tester.getRect(leavingFlight);
    expect(flying.width, greaterThan(from.width));
    expect(flying.height, greaterThan(from.height * 0.9));
    final paragraph = tester.renderObject<RenderParagraph>(leavingFlight);
    expect(
      paragraph.text.style?.decoration ?? TextDecoration.none,
      TextDecoration.none,
    );

    await tester.pumpAndSettle();
    final to = tester.getRect(arriving);
    expect(to.width, greaterThan(from.width));

    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      find.ancestor(
        of: find.text('7 首，更新于昨天 10:30'),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(leaving), from);
  });
}
