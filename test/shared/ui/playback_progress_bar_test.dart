import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/playback_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows elapsed and total time and speaks them in words', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: const Center(
          child: PlaybackProgressBar(positionMs: 72000, durationMs: 317000),
        ),
      ),
    );

    expect(find.text('1:12'), findsOneWidget);
    expect(find.text('5:17'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(PlaybackProgressBar)),
      isSemantics(value: '1分12秒，共5分17秒'),
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('heightOf is the laid out height at text scale $scale, and '
        'the times fit a narrow bar', (tester) async {
      late double expected;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Center(
            // 两个时间按字号排开会比这更宽。
            child: SizedBox(
              width: 160,
              child: Builder(
                builder: (context) {
                  expected = PlaybackProgressBar.heightOf(context);
                  return const PlaybackProgressBar(
                    positionMs: 3723000,
                    durationMs: 7384000,
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(PlaybackProgressBar)).height,
        moreOrLessEquals(expected, epsilon: 0.01),
      );
    });
  }
}
