import 'package:alisten/app/mini_player.dart';
import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/domain/history/listen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/history/history_test_doubles.dart';
import '../features/lobby/lobby_test_doubles.dart';
import '../features/search/search_test_doubles.dart';
import '../features/search/share_test_doubles.dart';
import 'app_test_harness.dart';
import 'idle_frames.dart';

const _roomId = '123e4567-e89b-42d3-a456-426614174000';

void main() {
  testWidgets('pages without a room draw nothing while left alone', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()
        ..rooms = [roomListing(id: _roomId, slug: 'listen')]
        ..listens = _history(),
      credentials: FakeCredentialStore()..memberToken = 'member-token',
    );
    final router = appContainer(tester).read(routerProvider);

    expect(await idleFrames(tester), 0, reason: 'lobby');
    router.go('/history');
    expect(await idleFrames(tester), 0, reason: 'history');
    expect(find.text('歌 0'), findsOneWidget);
    router.go('/settings');
    expect(await idleFrames(tester), 0, reason: 'settings');
  });

  testWidgets('the room page draws only the aurora in every mode', (
    tester,
  ) async {
    final room = await enterBusyRoom(tester);

    for (final mode in RoomMode.values) {
      room.router.go(mode.routeIn('listen'));
      expect(
        await idleFrames(tester),
        lessThanOrEqualTo(roomPageFrames),
        reason: mode.name,
      );
    }
  });

  testWidgets('waiting for the next word line adds no frames', (tester) async {
    final room = await enterBusyRoom(
      tester,
      lyricWords: '[0,1000](0,1000,0)一\n[5000,1000](5000,1000,0)二',
    );

    room.router.go(RoomMode.lyrics.routeIn('listen'));

    expect(await idleFrames(tester), lessThanOrEqualTo(roomPageFrames));
  });

  testWidgets('a break with dots to move stays within the rate of a sung '
      'line', (tester) async {
    final room = await enterBusyRoom(
      tester,
      lyricWords: '[100000,1000](100000,1000,0)字',
    );

    room.router.go(RoomMode.lyrics.routeIn('listen'));

    expect(await idleFrames(tester), lessThanOrEqualTo(62 + roomPageFrames));
  });

  testWidgets('a word line being sung draws about 60 frames a second, not '
      'one for each refresh of the screen', (tester) async {
    final room = await enterBusyRoom(
      tester,
      lyricWords: '[0,170000](0,170000,0)字',
    );

    room.router.go(RoomMode.lyrics.routeIn('listen'));

    expect(await idleFrames(tester), inInclusiveRange(40, 62 + roomPageFrames));
  });

  testWidgets('pages over an active room draw no more than the half-second '
      'refreshes', (tester) async {
    final room = await enterBusyRoom(tester);

    for (final path in ['/', '/history', '/settings', '/playlists']) {
      room.router.go(path);
      expect(
        await idleFrames(tester),
        lessThanOrEqualTo(periodicFrames),
        reason: path,
      );
      expect(find.byType(MiniPlayer), findsOneWidget, reason: path);
    }
  });

  testWidgets('the song search, with recommendations and a link on the '
      'clipboard, and a playlist draw nothing continuously', (tester) async {
    final page = await SearchPage.open(
      tester,
      clipboard: FakeClipboardSource(neteaseShareText),
    );
    expect(find.text('为你推荐'), findsOneWidget);
    expect(find.text('recommended'), findsOneWidget);
    expect(find.text('点剪贴板里的链接'), findsOneWidget);
    expect(await idleFrames(tester), lessThanOrEqualTo(periodicFrames));

    page.router.push('/r/listen/playlists/netease/1001').ignore();
    expect(await idleFrames(tester), lessThanOrEqualTo(periodicFrames));
    expect(find.text('song-0'), findsOneWidget);
  });
}

List<Listen> _history() {
  return [
    for (var index = 0; index < 5; index++)
      heard('歌 $index', at: DateTime(2026, 11, 1).millisecondsSinceEpoch),
  ];
}
