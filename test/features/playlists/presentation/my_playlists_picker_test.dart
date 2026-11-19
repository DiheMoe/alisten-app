import 'package:alisten/features/playlists/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playlists_page_harness.dart';
import '../playlists_test_doubles.dart';

void main() {
  late FakePlaylistApi server;

  setUp(() {
    server = FakePlaylistApi()
      ..playlists.addAll([
        favoritesPlaylist,
        playlist('run', name: '夜跑', trackCount: 1),
        playlist('ride', name: '通勤', trackCount: 1),
      ])
      ..contents['fav'] = []
      ..contents['run'] = [song('a')]
      ..contents['ride'] = [song('x')];
  });

  Widget picker() => CustomScrollView(
    slivers: [
      MyPlaylistsPicker(filter: '', onPick: (_, _) {}, onOpenAccount: () {}),
    ],
  );

  testWidgets('with nothing in favorites it starts on the first playlist that '
      'has songs', (tester) async {
    await pumpPlaylistsPage(tester, picker(), playlists: server);
    await settlePage(tester);

    expect(find.text('歌a'), findsOneWidget);
    expect(find.text('这个歌单还是空的'), findsNothing);
  });

  testWidgets('closed and opened again, it starts on the playlist chosen in '
      'it last time', (tester) async {
    final showing = ValueNotifier(true);
    addTearDown(showing.dispose);
    await pumpPlaylistsPage(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: showing,
        builder: (_, shown, _) => shown ? picker() : const SizedBox(),
      ),
      playlists: server,
    );
    await settlePage(tester);
    await tester.tap(find.text('通勤'));
    await settlePage(tester);
    expect(find.text('歌x'), findsOneWidget);

    showing.value = false;
    await settlePage(tester);
    showing.value = true;
    await settlePage(tester);
    expect(find.text('歌x'), findsOneWidget);
  });
}
