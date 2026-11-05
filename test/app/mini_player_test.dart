import 'dart:async';

import 'package:alisten/app/mini_player.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/room/room_fixtures.dart';
import '../features/lobby/lobby_test_doubles.dart';
import '../features/room/room_test_doubles.dart';
import 'app_test_harness.dart';

const _roomId = '123e4567-e89b-42d3-a456-426614174000';

Finder _control(String label) => find.byWidgetPredicate(
  (widget) => widget is IconCircleButton && widget.semanticLabel == label,
);

Future<
  ({
    FakeRoomTransportFactory rooms,
    ProviderContainer container,
    Future<void> Function() settle,
  })
>
_openedRoom(
  WidgetTester tester, {
  String? lyric,
  List<Override> overrides = const [],
}) async {
  final rooms = FakeRoomTransportFactory();
  await pumpAlistenApp(
    tester,
    api: FakeAlistenApi()..rooms = [roomListing(id: _roomId, slug: 'listen')],
    credentials: FakeCredentialStore()..tickets[_roomId] = 'saved-ticket',
    rooms: rooms,
    overrides: [currentLyricProvider.overrideWithValue(lyric), ...overrides],
  );
  final container = appContainer(tester);
  Future<void> settle() async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  unawaited(container.read(roomControllerProvider.notifier).openRoom('listen'));
  await tester.pump();
  rooms.last.emitHello(
    testRoomSnapshot().copyWith(
      term: 1,
      seq: 1,
      room: const RoomInfo(
        id: _roomId,
        name: '一起听',
        description: '',
        kind: RoomKind.ephemeral,
      ),
    ),
  );
  await settle();
  return (rooms: rooms, container: container, settle: settle);
}

void main() {
  testWidgets('the bar shows the line being sung in place of the artist', (
    tester,
  ) async {
    await _openedRoom(tester, lyric: '故事的小黄花');

    expect(find.text('故事的小黄花'), findsOneWidget);
    expect(
      find.text('一起听 · ${testNowPlaying.entry.meta.artist}'),
      findsNothing,
    );
  });

  testWidgets('between lines the bar names the room and the artist', (
    tester,
  ) async {
    await _openedRoom(tester);

    expect(
      find.text('一起听 · ${testNowPlaying.entry.meta.artist}'),
      findsOneWidget,
    );
  });

  testWidgets('trouble with the connection comes before the lyrics', (
    tester,
  ) async {
    final (:rooms, :container, :settle) = await _openedRoom(
      tester,
      lyric: '故事的小黄花',
    );

    rooms.last.disconnect();
    await settle();

    expect(find.text('故事的小黄花'), findsNothing);
    // 让重连的定时器走完。
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('the progress ends in a glowing head', (tester) async {
    await _openedRoom(
      tester,
      overrides: [
        playbackControllerProvider.overrideWithBuild(
          (ref, _) => const LocalPlaybackState(
            status: LocalPlaybackStatus.playing,
            positionMs: 30000,
            durationMs: 60000,
          ),
        ),
      ],
    );

    expect(
      find.byType(MiniPlayerProgress),
      paints
        ..circle()
        ..circle(),
    );
  });

  testWidgets('outside the room the mini player shows what the active room '
      'plays and leads back to it', (tester) async {
    final rooms = FakeRoomTransportFactory();
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing(id: _roomId, slug: 'listen')],
      credentials: FakeCredentialStore()..tickets[_roomId] = 'saved-ticket',
      rooms: rooms,
    );
    final container = appContainer(tester);
    final router = container.read(routerProvider);
    Future<void> settle() async {
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.byType(MiniPlayer), findsNothing);

    // 与启动时一样，进入房间但不显示房间页。
    unawaited(
      container.read(roomControllerProvider.notifier).openRoom('listen'),
    );
    await tester.pump();
    rooms.last.emitHello(
      testRoomSnapshot().copyWith(
        term: 1,
        seq: 1,
        room: const RoomInfo(
          id: _roomId,
          name: '一起听',
          description: '',
          kind: RoomKind.ephemeral,
        ),
      ),
    );
    await settle();

    final player = find.byType(MiniPlayer);
    expect(player, findsOneWidget);
    expect(
      find.descendant(of: player, matching: find.text('歌曲')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: player,
        matching: find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == 'cover-entry-id',
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.descendant(of: player, matching: find.text('歌曲')));
    await settle();
    expect(router.state.uri.path, '/r/$_roomId');
    expect(find.byType(MiniPlayer), findsNothing);

    router.go('/settings');
    await settle();
    await tester.fling(player, const Offset(0, -120), 800);
    await settle();
    expect(router.state.uri.path, '/r/$_roomId');
  });

  for (final (what, code, reason) in [
    ('gone', 4404, '房间不存在或已经关闭。'),
    ('too old for the app', 4426, '客户端协议版本过旧，请升级 Alisten。'),
  ]) {
    testWidgets('a room that is $what stays with its reason and a close '
        'button that leaves it', (tester) async {
      final (:rooms, :container, :settle) = await _openedRoom(tester);
      final player = find.byType(MiniPlayer);
      expect(_control('暂停本机播放'), findsOneWidget);
      expect(_control('关闭'), findsNothing);

      rooms.last.disconnect(code: code);
      await settle();

      expect(player, findsOneWidget);
      expect(
        find.descendant(of: player, matching: find.text('一起听')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: player, matching: find.text(reason)),
        findsOneWidget,
      );
      expect(_control('暂停本机播放'), findsNothing);
      expect(_control('恢复本机播放'), findsNothing);
      expect(_control('关闭'), findsOneWidget);

      await tester.tap(_control('关闭'));
      await settle();
      // 释放连接要等流取消，只有真实事件循环能完成。
      await tester.runAsync(pumpEventQueue);

      expect(player, findsNothing);
      final room = container.read(roomControllerProvider);
      expect(room.activeRoomId, isNull);
      expect(room.failure, isNull);
      expect(rooms.last.stopCalls, greaterThan(0));
    });
  }

  testWidgets('between two tracks the bar says it waits for the next one '
      'instead of offering a pause that does nothing', (tester) async {
    final semantics = tester.ensureSemantics();
    final rooms = FakeRoomTransportFactory();
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing(id: _roomId, slug: 'listen')],
      credentials: FakeCredentialStore()..tickets[_roomId] = 'saved-ticket',
      rooms: rooms,
    );
    final container = appContainer(tester);
    unawaited(
      container.read(roomControllerProvider.notifier).openRoom('listen'),
    );
    await tester.pump();
    rooms.last.emitHello(
      testRoomSnapshot(),
      testNowPlaying.startedAtMs + testNowPlaying.durationMs + 1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final player = find.byType(MiniPlayer);
    expect(player, findsOneWidget);
    expect(_control('暂停本机播放'), findsNothing);
    expect(_control('恢复本机播放'), findsNothing);
    final waiting = find.descendant(
      of: player,
      matching: find.bySemanticsLabel('等待下一首'),
    );
    expect(waiting, findsOneWidget);
    expect(
      tester.getSemantics(waiting),
      isSemantics(label: '等待下一首', isButton: false, hasTapAction: false),
    );
    semantics.dispose();
  });

  testWidgets('a bar closed while it fades out keeps showing what it showed', (
    tester,
  ) async {
    final (:rooms, :container, :settle) = await _openedRoom(tester);
    rooms.last.disconnect(code: 4404);
    await settle();
    final player = find.byType(MiniPlayer);
    expect(player, findsOneWidget);

    await tester.tap(_control('关闭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 已退出房间，迷你播放器仍在淡出途中。
    expect(container.read(roomControllerProvider).activeRoomId, isNull);
    expect(player, findsOneWidget);
    expect(
      find.descendant(of: player, matching: find.text('一起听')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: player, matching: find.text('房间不存在或已经关闭。')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: player, matching: find.text('房间')),
      findsNothing,
    );
    expect(
      find.descendant(of: player, matching: find.text('房间暂时没有播放')),
      findsNothing,
    );

    await settle();
    expect(player, findsNothing);
    await tester.runAsync(pumpEventQueue);
  });

  testWidgets('a failure that entering again can fix keeps the bar leading '
      'back to the room, with no close button', (tester) async {
    final (:rooms, :container, :settle) = await _openedRoom(tester);
    final router = container.read(routerProvider);

    rooms.last.disconnect(code: 4401);
    await settle();

    final player = find.byType(MiniPlayer);
    expect(player, findsOneWidget);
    expect(
      find.descendant(of: player, matching: find.text('房间票据已失效，请重新验证后进入。')),
      findsOneWidget,
    );
    expect(_control('关闭'), findsNothing);

    await tester.tap(find.descendant(of: player, matching: find.text('一起听')));
    await settle();
    expect(router.state.uri.path, '/r/$_roomId');
    expect(
      container.read(roomControllerProvider).activeRoomId,
      _roomId,
      reason: 'opening the room does not leave it',
    );
  });

  testWidgets('a room refused before its first snapshot is still named by '
      'its listing', (tester) async {
    final api = FakeAlistenApi()
      ..rooms = [roomListing(id: _roomId, slug: 'listen')]
      ..ticketError = const ApiException(
        code: 'UNAUTHORIZED',
        message: '房间密码错误',
        status: 401,
      );
    await pumpAlistenApp(tester, api: api);
    final container = appContainer(tester);

    await container.read(roomControllerProvider.notifier).openRoom('listen');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final player = find.byType(MiniPlayer);
    expect(player, findsOneWidget);
    expect(
      find.descendant(of: player, matching: find.text('一起听')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: player, matching: find.text('房间')),
      findsNothing,
    );
    expect(
      find.descendant(of: player, matching: find.text('房间密码错误')),
      findsOneWidget,
    );
  });

  testWidgets('the bar is rebuilt by what it shows, not by every change of '
      'the room', (tester) async {
    final (:rooms, :container, :settle) = await _openedRoom(tester);
    var builds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is MiniPlayer) builds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    final before = container.read(roomControllerProvider).notices;

    rooms.last.emit(
      const RoomEventReceived(
        ChatMessageEvent(
          term: 1,
          seq: 2,
          member: testMember,
          content: '晚上好',
          sentAtMs: 1,
        ),
      ),
    );
    await settle();
    expect(container.read(roomControllerProvider).notices, isNot(before));
    expect(builds, 0);

    rooms.last.disconnect(code: 1006);
    await settle();
    expect(builds, greaterThan(0), reason: 'a lost connection is shown');
    unawaited(rooms.last.stop());
  });
}
