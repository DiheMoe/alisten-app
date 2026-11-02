import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/segmented_pills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final (first, second) = (a.computeLuminance(), b.computeLuminance());
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

Color _fillOf(WidgetTester tester, Finder box) =>
    (tester.widget<DecoratedBox>(box).decoration as BoxDecoration).color!;

BoxDecoration _thumbDecoration(WidgetTester tester) =>
    tester
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: find.byType(AnimatedAlign),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

void main() {
  for (final scale in [1.0, 1.5, 2.0, 3.0]) {
    testWidgets('heightOf is the laid out height of one-line segments at text '
        'scale $scale', (tester) async {
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
            child: SizedBox(
              width: 400,
              child: Builder(
                builder: (context) {
                  expected = SegmentedPills.heightOf(context);
                  return SegmentedPills(
                    segments: const [
                      PillSegment(
                        value: 'queue',
                        label: '队列',
                        icon: Icons.queue_music_rounded,
                      ),
                      PillSegment(value: 'chat', label: '聊天'),
                    ],
                    selected: 'chat',
                    onChanged: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(SegmentedPills<String>)).height,
        moreOrLessEquals(expected, epsilon: 0.01),
      );
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('the chosen segment stands out from the track and is '
        'announced as selected, in the ${brightness.name} theme', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final scheme = AlistenColors.brandScheme(brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAlistenTheme(scheme),
          home: Center(
            child: SizedBox(
              width: 320,
              child: SegmentedPills(
                segments: const [
                  PillSegment(value: 'queue', label: '队列'),
                  PillSegment(value: 'chat', label: '聊天'),
                ],
                selected: 'chat',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      final pills = find.byType(SegmentedPills<String>);
      final track = _fillOf(
        tester,
        find.descendant(of: pills, matching: find.byType(DecoratedBox)).first,
      );
      final thumb = _fillOf(
        tester,
        find
            .descendant(
              of: find.byType(AnimatedAlign),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );

      // 分段控件常放在玻璃面板中：轨道叠在面板上，滑块叠在轨道上。
      final panel = Color.alphaBlend(
        AlistenColors.fromScheme(scheme).glassFill,
        scheme.surface,
      );
      final trackShown = Color.alphaBlend(track, panel);
      expect(
        _contrast(Color.alphaBlend(thumb, trackShown), trackShown),
        greaterThanOrEqualTo(1.5),
      );
      // 滑块轮廓是辨认选中项的边界，与轨道须达到非文字内容的 3:1 对比度。
      final stroke = (_thumbDecoration(tester).border! as Border).top.color;
      expect(
        _contrast(Color.alphaBlend(stroke, trackShown), trackShown),
        greaterThanOrEqualTo(3),
      );
      expect(
        tester.getSemantics(find.text('聊天')),
        isSemantics(isSelected: true, isInMutuallyExclusiveGroup: true),
      );
      expect(
        tester.getSemantics(find.text('队列')),
        isSemantics(isSelected: false, isInMutuallyExclusiveGroup: true),
      );
      semantics.dispose();
    });
  }
}
