import 'package:alisten/app/router.dart';
import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/room/room_fixtures.dart';
import '../features/lobby/lobby_test_doubles.dart';
import '../features/playlists/playlists_test_doubles.dart';
import '../features/room/room_test_doubles.dart';
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
    await tester.tap(find.bySemanticsLabel('以列表显示'));
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

  testWidgets('the history rows save their songs from their menu', (
    tester,
  ) async {
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

    expect(find.byType(SaveToPlaylistButton), findsNothing);
    await tester.tap(find.bySemanticsLabel('《晴天》的更多操作'));
    await settle(tester);
    expect(find.text('保存到歌单'), findsOneWidget);
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
    await tester.tap(find.bySemanticsLabel('《晴天》的更多操作'));
    await settle(tester);
    await tester.tap(find.text('保存到歌单'));
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

    // 队列里正在播放和等待中的都是这首歌，保存在各行的“⋯”里；收拢的播放器上
    // 没有按钮。从房间打开的面板沿用房间的配色，而不是房间外的品牌配色。
    router.go('/r/listen/queue');
    await settle();
    expect(find.byType(SaveToPlaylistButton), findsNothing);
    final menu = find.bySemanticsLabel('《歌曲》的更多操作');
    expect(menu, findsNWidgets(2));
    final roomColors = AlistenColors.of(tester.element(menu.first));
    await tester.tap(menu.first);
    await settle();
    await tester.tap(find.text('保存到歌单'));
    await settle();
    expect(find.text('去账号设置'), findsOneWidget);
    expect(AlistenColors.of(tester.element(find.text('去账号设置'))), roomColors);
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

  group('song search and my playlists', () {
    Future<FakeRoomTransportFactory> openSearch(
      WidgetTester tester, {
      required bool signedIn,
      FakePlaylistApi? server,
    }) async {
      tester.view
        ..physicalSize = const Size(360, 780) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final rooms = FakeRoomTransportFactory();
      final api = FakeAlistenApi()
        ..rooms = [roomListing(id: testRoomId, slug: 'listen')];
      final credentials = FakeCredentialStore()
        ..tickets[testRoomId] = 'saved-ticket';
      if (signedIn) {
        api.account = testAccount;
        credentials.memberToken = accountToken;
      }
      await pumpAlistenApp(
        tester,
        api: api,
        credentials: credentials,
        rooms: rooms,
        playlists: server,
      );
      appContainer(tester).read(routerProvider).go('/r/listen/search');
      await settle(tester);
      rooms.last
        ..responses.addAll(defaultSearchAnswers())
        ..emitHello(testRoomSnapshot().copyWith(term: 1, seq: 1));
      await settle(tester);
      return rooms;
    }

    testWidgets('my playlists are a third source of song search: a playlist '
        'is chosen and its songs are picked without leaving the page', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final server = FakePlaylistApi()
        ..playlists.addAll([
          favoritesPlaylist,
          playlist('pl-1', name: '夜跑', trackCount: 2),
        ])
        ..contents['fav'] = [song('z', title: '晴天')]
        ..contents['pl-1'] = [song('a'), song('b')];
      final rooms = await openSearch(tester, signedIn: true, server: server);
      final router = appContainer(tester).read(routerProvider);
      expect(find.text('为你推荐'), findsOneWidget);

      await tester.tap(find.text('我的歌单'));
      await settle(tester);
      // 换成歌单之后不再有平台的推荐；默认选中排在最前的“我喜欢”。
      expect(find.text('为你推荐'), findsNothing);
      expect(find.bySemanticsLabel('点歌《晴天》'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('夜跑'));
      await settle(tester);
      expect(find.bySemanticsLabel('点歌《晴天》'), findsNothing);
      expect(find.bySemanticsLabel('点歌《歌b》'), findsOneWidget);

      rooms.last.responses['queue.add'] = {'entry': entryJson('歌a')};
      await tester.tap(find.bySemanticsLabel('点歌《歌a》'));
      await settle(tester);
      expect([
        for (final request in rooms.last.requests)
          if (request['type'] == 'queue.add') request,
      ], hasLength(1));
      expect(router.state.uri.path, '/r/listen/search');

      // 输入框筛选选中的歌单，不去搜索平台。
      await tester.enterText(find.byType(EditableText), '歌b');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(find.bySemanticsLabel('点歌《歌b》'), findsOneWidget);
      expect(find.bySemanticsLabel('点歌《歌a》'), findsNothing);
      expect(
        rooms.last.requests.where((r) => r['type'] == 'search.tracks'),
        isEmpty,
      );

      await tester.tap(find.text('QQ 音乐'));
      await settle(tester);
      expect(find.text('为你推荐'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      semantics.dispose();
    });

    testWidgets('with many playlists, one is chosen from the list of all '
        'and its tag scrolls into view', (tester) async {
      final semantics = tester.ensureSemantics();
      final server = FakePlaylistApi()
        ..playlists.addAll([
          favoritesPlaylist,
          for (var i = 1; i <= 20; i++)
            playlist('pl-$i', name: '歌单$i', updatedAtMs: 100 - i),
        ])
        ..contents['pl-20'] = [song('a')];
      await openSearch(tester, signedIn: true, server: server);
      await tester.tap(find.text('我的歌单'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('歌单20').hitTestable(), findsNothing);

      await tester.tap(find.bySemanticsLabel('全部歌单'));
      await settle(tester);
      // 标签和面板里各有一个“歌单20”，后一个在面板里。
      await tester.ensureVisible(find.text('歌单20').last);
      await settle(tester);
      await tester.tap(find.text('歌单20').last);
      await settle(tester);

      expect(find.bySemanticsLabel('点歌《歌a》'), findsOneWidget);
      expect(find.text('歌单20').hitTestable(), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a sideways fling moves to the next source and back', (
      tester,
    ) async {
      final server = FakePlaylistApi()..playlists.add(favoritesPlaylist);
      await openSearch(tester, signedIn: true, server: server);
      const page = Offset(180, 600);

      await tester.flingFrom(page, const Offset(-200, 0), 1500);
      await settle(tester);
      expect(find.text('为你推荐'), findsOneWidget, reason: '网易云');
      expect(find.text('还没有歌单'), findsNothing);

      await tester.flingFrom(page, const Offset(-200, 0), 1500);
      await settle(tester);
      expect(find.text('为你推荐'), findsNothing, reason: '我的歌单');
      expect(find.text('这个歌单还是空的'), findsOneWidget);

      // 已经是最后一个来源，再甩不动。
      await tester.flingFrom(page, const Offset(-200, 0), 1500);
      await settle(tester);
      expect(find.text('这个歌单还是空的'), findsOneWidget);

      await tester.flingFrom(page, const Offset(200, 0), 1500);
      await settle(tester);
      expect(find.text('为你推荐'), findsOneWidget);

      // 竖向滚动不换来源。
      await tester.flingFrom(page, const Offset(0, -200), 1500);
      await settle(tester);
      expect(find.text('这个歌单还是空的'), findsNothing);
    });

    testWidgets('a guest who chooses my playlists is led to the account '
        'settings', (tester) async {
      await openSearch(tester, signedIn: false);

      await tester.tap(find.text('我的歌单'));
      await settle(tester);

      expect(find.text('去账号设置'), findsOneWidget);
      expect(find.text('为你推荐'), findsNothing);
    });
  });
}
