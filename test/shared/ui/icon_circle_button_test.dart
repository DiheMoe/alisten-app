import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child) {
    return MaterialApp(
      theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
      home: Center(child: child),
    );
  }

  testWidgets('a small button still takes 48 by 48 and is pressed once', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      app(
        IconCircleButton(
          icon: Icons.skip_next_rounded,
          semanticLabel: '投票切歌',
          diameter: 36,
          onPressed: () => presses++,
        ),
      ),
    );

    final size = tester.getSize(find.byType(IconCircleButton));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(find.bySemanticsLabel('投票切歌')),
      isSemantics(
        label: '投票切歌',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.bySemanticsLabel('投票切歌'));
    await tester.pumpAndSettle();
    expect(presses, 1);
  });

  testWidgets('a button without an action is announced as disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IconCircleButton(
          icon: Icons.skip_next_rounded,
          semanticLabel: '投票切歌',
          onPressed: null,
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('投票切歌')),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
  });
}
