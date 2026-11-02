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
                otherRoom: '/r/other',
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
}
