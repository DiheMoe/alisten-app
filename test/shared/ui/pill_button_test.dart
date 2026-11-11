import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a busy button says it is in progress, not a percentage, and ignores '
    'presses',
    (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          // 移除动画时转圈静止为部分填充的圆环。
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Center(
            child: PillButton(
              label: '点歌',
              busy: true,
              onPressed: () => presses++,
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.text('点歌')),
        isSemantics(label: '点歌', value: '进行中', isButton: true),
      );
      await tester.tap(find.text('点歌'), warnIfMissed: false);
      expect(presses, 0);
    },
  );

  testWidgets('a button that opens something says whether it is open; '
      'others have no expanded state', (tester) async {
    Future<void> show({bool? expanded}) => tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: Center(
          child: PillButton(label: '导入', expanded: expanded, onPressed: () {}),
        ),
      ),
    );

    await show();
    expect(
      tester.getSemantics(find.text('导入')),
      isSemantics(label: '导入', isButton: true, hasExpandedState: false),
    );

    await show(expanded: false);
    expect(
      tester.getSemantics(find.text('导入')),
      isSemantics(hasExpandedState: true, isExpanded: false),
    );

    await show(expanded: true);
    expect(
      tester.getSemantics(find.text('导入')),
      isSemantics(hasExpandedState: true, isExpanded: true),
    );
  });

  for (final scale in [1.0, 1.5, 2.0, 3.0]) {
    for (final large in [false, true]) {
      testWidgets('heightOf is the height of a one-line button at text scale '
          '$scale, large: $large', (tester) async {
        late double expected;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAlistenTheme(
              AlistenColors.brandScheme(Brightness.light),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Center(
              child: Builder(
                builder: (context) {
                  expected = PillButton.heightOf(context, large: large);
                  return PillButton(
                    label: '加入房间',
                    icon: Icons.login_rounded,
                    large: large,
                    onPressed: () {},
                  );
                },
              ),
            ),
          ),
        );

        expect(
          tester.getSize(find.byType(PillButton)).height,
          moreOrLessEquals(expected, epsilon: 1),
        );
      });
    }
  }
}
