import 'dart:convert';

import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/domain/history/play_record.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
      api: FakeAlistenApi()..rooms = [roomListing(id: _roomId, slug: 'listen')],
      preferences: {'alisten.play-history': _history()},
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

  testWidgets('pages over an active room draw no more than the half-second '
      'refreshes', (tester) async {
    final room = await enterBusyRoom(tester);

    for (final path in ['/', '/history', '/settings']) {
      room.router.go(path);
      expect(
        await idleFrames(tester),
        lessThanOrEqualTo(periodicFrames),
        reason: path,
      );
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

String _history() {
  return jsonEncode([
    for (var index = 0; index < 5; index++)
      PlayRecord(
        roomId: 'room',
        roomName: '一起听',
        serverOrigin: 'https://livehouse.dihe.moe',
        track: Track(source: TrackSource.netease, id: '$index'),
        meta: TrackMeta(
          title: '歌 $index',
          artist: '歌手',
          album: '专辑',
          coverUrl: '',
          pageUrl: '',
          durationMs: 180000,
        ),
        playedAtMs: DateTime(2026, 11, 1).millisecondsSinceEpoch,
      ).toJson(),
  ]);
}
