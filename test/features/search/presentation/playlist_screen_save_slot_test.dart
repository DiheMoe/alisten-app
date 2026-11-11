import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/app_test_harness.dart';

SearchState _searched(String name) => SearchState(
  results: SearchResults(
    playlists: [
      PlaylistSummary(
        source: TrackSource.netease,
        id: '1001',
        name: name,
        coverUrl: '',
        creator: '',
        description: '',
        trackCount: 2,
        playCount: 0,
      ),
    ],
  ),
);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool withSlot,
    String? searchedName,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await alistenAppOverrides(),
          if (searchedName != null)
            searchControllerProvider.overrideWithBuild(
              (ref, _) => _searched(searchedName),
            ),
        ],
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: PlaylistScreen(
            source: TrackSource.netease,
            id: '1001',
            onResult: (_, _) {},
            onNotice: (_) {},
            saveAsMine: withSlot ? (name) => Text('保存为 $name') : null,
          ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  testWidgets('a playlist opened without a search result is saved under the '
      'default name', (tester) async {
    await pump(tester, withSlot: true);

    expect(find.text('保存为 导入的歌单'), findsOneWidget);
  });

  testWidgets('a playlist opened from a search result is saved under its '
      'own name', (tester) async {
    await pump(tester, withSlot: true, searchedName: '华语流行');

    expect(find.text('保存为 华语流行'), findsOneWidget);
  });

  testWidgets('a search result without a name is saved under the default '
      'name', (tester) async {
    await pump(tester, withSlot: true, searchedName: '');

    expect(find.text('保存为 导入的歌单'), findsOneWidget);
  });

  testWidgets('a search result whose name is only spaces is saved under the '
      'default name', (tester) async {
    await pump(tester, withSlot: true, searchedName: ' \u3000 ');

    expect(find.text('保存为 导入的歌单'), findsOneWidget);
  });

  testWidgets('without a slot the header has nothing extra', (tester) async {
    await pump(tester, withSlot: false);

    expect(find.textContaining('保存为'), findsNothing);
  });
}
