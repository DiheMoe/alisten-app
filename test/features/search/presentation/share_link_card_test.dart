import 'package:alisten/features/search/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/app_test_harness.dart';

void main() {
  testWidgets('another room is just entered while no room is in use', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final entered = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(),
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Scaffold(
            body: ShareLinkCard(
              heading: '剪贴板里的房间链接',
              share: const ResolvedShare(
                link: 'https://livehouse.dihe.moe/r/other',
                platform: LinkPlatform.web,
                problem: LinkProblem.roomLink,
                linkRoute: '/r/other',
              ),
              onResult: (_, _) {},
              onEnterRoom: entered.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('进入这个房间'), findsOneWidget);
    expect(find.bySemanticsLabel('进入这个房间'), findsOneWidget);
    expect(find.text('离开当前房间并进入'), findsNothing);

    await tester.tap(find.text('进入这个房间'));
    expect(entered, ['/r/other']);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('a shared playlist is opened from its card', (tester) async {
    final semantics = tester.ensureSemantics();
    final opened = <String>[];
    var dismissed = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(),
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Scaffold(
            body: ShareLinkCard(
              heading: '剪贴板里的歌单链接',
              share: const ResolvedShare(
                link: 'https://livehouse.dihe.moe/s/AbCdEfGhIjKlMnOpQrStUv',
                platform: LinkPlatform.web,
                problem: LinkProblem.sharedPlaylistLink,
                linkRoute: '/s/AbCdEfGhIjKlMnOpQrStUv',
              ),
              onResult: (_, _) {},
              onDismiss: () => dismissed++,
              onEnterRoom: opened.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('打开这个歌单'), findsOneWidget);
    expect(find.text('离开当前房间并进入'), findsNothing);
    expect(find.bySemanticsLabel('不打开这个歌单'), findsOneWidget);

    await tester.tap(find.text('打开这个歌单'));
    expect(opened, ['/s/AbCdEfGhIjKlMnOpQrStUv']);
    await tester.tap(find.bySemanticsLabel('不打开这个歌单'));
    expect(dismissed, 1);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });
}
