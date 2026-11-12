import 'package:alisten/app/router.dart';
import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lobby/lobby_test_doubles.dart';
import '../features/playlists/playlists_test_doubles.dart';
import '../features/search/search_test_doubles.dart';
import 'app_test_harness.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  List<double> iconSizes(WidgetTester tester) => [
    for (final button in tester.widgetList<SaveToPlaylistButton>(
      find.byType(SaveToPlaylistButton),
    ))
      button.iconSize,
  ];

  testWidgets('the lobby opens my playlists, and the view chosen there is '
      'kept for the next visit', (tester) async {
    final semantics = tester.ensureSemantics();
    final server = FakePlaylistApi()
      ..playlists.addAll([
        favoritesPlaylist,
        playlist('pl-1', name: '夜跑', updatedAtMs: 9),
        playlist('pl-2', name: '晨跑', updatedAtMs: 5),
      ]);
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()..account = testAccount,
      credentials: FakeCredentialStore()..memberToken = accountToken,
      playlists: server,
    );
    final container = appContainer(tester);
    final router = container.read(routerProvider);

    await tester.tap(find.bySemanticsLabel('我的歌单'));
    await settle(tester);
    expect(router.state.uri.path, '/playlists');
    await tester.tap(find.bySemanticsLabel('列表'));
    await settle(tester);

    router.go('/');
    await settle(tester);
    router.go('/playlists');
    await settle(tester);

    expect(
      container
          .read(sharedPreferencesProvider)
          .getString('alisten.playlists-view'),
      contains('"view":"list"'),
    );
    expect(
      tester.getTopLeft(find.text('夜跑')).dx,
      tester.getTopLeft(find.text('晨跑')).dx,
    );

    await tester.tap(find.text('夜跑'));
    await settle(tester);
    expect(router.state.uri.path, '/playlists/pl-1');
    router.pop();
    await settle(tester);
    expect(router.state.uri.path, '/playlists');
    semantics.dispose();
  });

  testWidgets('a playlist deleted from its page leads back to the list', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final server = FakePlaylistApi()
      ..playlists.addAll([favoritesPlaylist, playlist('pl-1', name: '夜跑')])
      ..contents['pl-1'] = [];
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()..account = testAccount,
      credentials: FakeCredentialStore()..memberToken = accountToken,
      playlists: server,
    );
    final router = appContainer(tester).read(routerProvider);
    router.go('/playlists/pl-1');
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('“夜跑”的更多操作'));
    await settle(tester);
    await tester.tap(find.text('删除'));
    await settle(tester);
    await tester.tap(find.widgetWithText(PillButton, '删除'));
    await settle(tester);

    expect(router.state.uri.path, '/playlists');
    semantics.dispose();
  });

  testWidgets('the history rows can save their songs', (tester) async {
    final semantics = tester.ensureSemantics();
    final api = FakeAlistenApi()
      ..listens.add(
        Listen(
          track: const Track(source: TrackSource.netease, id: '1'),
          meta: const TrackMeta(
            title: '晴天',
            artist: '周杰伦',
            album: '',
            coverUrl: '',
            pageUrl: '',
            durationMs: 0,
          ),
          heardAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    await pumpAlistenApp(
      tester,
      api: api,
      credentials: FakeCredentialStore()..memberToken = 'member-token',
    );
    appContainer(tester).read(routerProvider).go('/history');
    await settle(tester);

    expect(find.bySemanticsLabel('把《晴天》保存到歌单'), findsOneWidget);
    expect(iconSizes(tester), [AlistenSizes.iconSm]);
    semantics.dispose();
  });

  testWidgets('a save panel left open after a link replaced its page still '
      'leads a guest to the account settings', (tester) async {
    final semantics = tester.ensureSemantics();
    final api = FakeAlistenApi()
      ..listens.add(
        Listen(
          track: const Track(source: TrackSource.netease, id: '1'),
          meta: const TrackMeta(
            title: '晴天',
            artist: '周杰伦',
            album: '',
            coverUrl: '',
            pageUrl: '',
            durationMs: 0,
          ),
          heardAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    await pumpAlistenApp(
      tester,
      api: api,
      credentials: FakeCredentialStore()..memberToken = 'member-token',
    );
    final router = appContainer(tester).read(routerProvider);
    router.go('/history');
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('把《晴天》保存到歌单'));
    await settle(tester);
    expect(find.text('去账号设置'), findsOneWidget);

    // 面板在根导航器上，换掉外壳里的页面时它还开着。
    router.go('/');
    await settle(tester);
    expect(find.byType(SaveToPlaylistButton), findsNothing);
    expect(find.text('去账号设置'), findsOneWidget);
    await tester.tap(find.text('去账号设置'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(router.state.uri.path, '/settings');
    semantics.dispose();
  });

  testWidgets('the player and the queue of a room can save their songs; the '
      'collapsed player cannot', (tester) async {
    final semantics = tester.ensureSemantics();
    final (:router, :settle, rooms: _) = await enterRoom(tester);

    // testNowPlaying 的歌名是“歌曲”（test/domain/room/room_fixtures.dart）。
    expect(find.bySemanticsLabel('把《歌曲》保存到歌单'), findsOneWidget);
    expect(iconSizes(tester), [AlistenSizes.icon]);

    // 队列里正在播放和等待中的都是这首歌；收拢的播放器上没有按钮。
    router.go('/r/listen/queue');
    await settle();
    expect(find.bySemanticsLabel('把《歌曲》保存到歌单'), findsNWidgets(2));
    expect(iconSizes(tester), [AlistenSizes.iconSm, AlistenSizes.iconSm]);
    semantics.dispose();
  });

  testWidgets('a save panel left open after a link replaced the room page '
      'still leads a guest to the account settings', (tester) async {
    final semantics = tester.ensureSemantics();
    final (:router, :settle, rooms: _) = await enterRoom(tester);
    await tester.tap(find.bySemanticsLabel('把《歌曲》保存到歌单'));
    await settle();
    expect(find.text('去账号设置'), findsOneWidget);

    // 换到另一个房间的链接：房间页原地更新，换下了房间内容，面板还开着。
    router.go('/r/other');
    await settle();
    expect(find.byType(SaveToPlaylistButton), findsNothing);
    expect(find.text('去账号设置'), findsOneWidget);
    await tester.tap(find.text('去账号设置'));
    await settle();

    expect(tester.takeException(), isNull);
    expect(router.state.uri.path, '/settings');
    semantics.dispose();
  });

  testWidgets('a NetEase or QQ Music playlist offers to be saved under its '
      'name, or under the default one when opened from a link', (tester) async {
    final page = await SearchPage.open(tester);
    page.transport.responses['search.playlists'] = {
      'items': [playlistJson('1001', name: '华语流行')],
      'total': 1,
    };
    await tester.tap(find.text('网易云'));
    await page.settle();
    await page.search('晴天');
    await tester.tap(find.text('歌单').first);
    await page.settle();
    await tester.tap(find.text('华语流行'));
    await page.settle();

    SavePlatformPlaylistButton button() =>
        tester.widget(find.byType(SavePlatformPlaylistButton));
    expect(button().name, '华语流行');
    expect(button().source, TrackSource.netease);
    expect(button().playlistId, '1001');

    page.router.go('/r/listen/playlists/netease/2002');
    await page.settle();
    expect(button().name, '导入的歌单');
    expect(button().playlistId, '2002');

    page.router.go('/r/listen/playlists/qq/3003');
    await page.settle();
    expect(button().name, '导入的歌单');
    expect(button().source, TrackSource.qq);
    expect(button().playlistId, '3003');
    final request = page.transport.requests.lastWhere(
      (request) => request['type'] == 'playlist.tracks',
    );
    expect(request['data'], {'source': 'qq', 'playlistId': '3003'});
  });
}
