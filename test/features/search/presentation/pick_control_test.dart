import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/app_test_harness.dart';

void main() {
  testWidgets('a reason the song cannot be picked disables it and is what '
      'a screen reader hears', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(),
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Scaffold(
            body: Column(
              children: [
                PickControl(
                  track: const Track(
                    source: TrackSource.link,
                    id: 'https://example.com/a.mp3',
                  ),
                  title: '网页里的歌',
                  blockedReason: '临时房间不能点链接里的歌',
                  onPick: (_, _) {},
                ),
                PickControl(
                  track: const Track(source: TrackSource.netease, id: '1'),
                  title: '晴天',
                  onPick: (_, _) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('临时房间不能点链接里的歌'), findsOneWidget);
    expect(find.bySemanticsLabel('点歌《网页里的歌》'), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('临时房间不能点链接里的歌')),
      isSemantics(isEnabled: false, hasEnabledState: true, isButton: true),
    );
    expect(find.bySemanticsLabel('点歌《晴天》'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('a pick button of a row is glass with a brand icon; a featured '
      'one is filled with the brand', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(),
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Scaffold(
            body: Column(
              children: [
                PickControl(
                  key: const ValueKey('row'),
                  track: const Track(source: TrackSource.netease, id: '1'),
                  title: '晴天',
                  onPick: (_, _) {},
                ),
                PickControl(
                  key: const ValueKey('featured'),
                  track: const Track(source: TrackSource.netease, id: '2'),
                  title: '七里香',
                  tone: PickTone.filled,
                  onPick: (_, _) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final colors = AlistenColors.of(tester.element(find.byType(Column)));
    Color? fill(String key) =>
        (tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: find.byKey(ValueKey(key)),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .color;
    Color? ink(String key) => tester
        .widget<Icon>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byIcon(AlistenIcons.plusBold),
          ),
        )
        .color;

    expect(fill('row'), colors.glassFill);
    expect(ink('row'), colors.brand);
    expect(fill('featured'), colors.brand);
    expect(ink('featured'), colors.onBrand);
    await tester.pumpWidget(const SizedBox());
  });
}
