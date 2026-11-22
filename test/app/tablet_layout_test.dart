import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/shared/ui/segmented_pills.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/room/room_fixtures.dart';
import '../features/lobby/lobby_test_doubles.dart';
import '../features/playback/playback_test_doubles.dart' show FakeAudioEngine;
import 'app_test_harness.dart';

const _tablet = Size(1024, 1366);
const _ipadLandscape = Size(1194, 834);

/// 平板竖屏和横屏。
final _tablets = ValueVariant({_tablet, const Size(1366, 1024)});

/// 常见 iPad 横屏及分屏尺寸：2/3 分屏、经典 1024、mini、11 寸、13 寸。
final _landscapeIpads = ValueVariant({
  const Size(840, 600),
  const Size(1024, 768),
  const Size(1133, 744),
  _ipadLandscape,
  const Size(1366, 1024),
});

// 不查文字对比度：测试字体不绘制中文和图标，右栏切换项的区域里只剩房间深色
// 背景的渐变，比较的是两种背景色。房间文字的对比度由颜色测试保证。
Future<void> _expectAccessible(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

void main() {
  testWidgets('a tablet shows the player beside the queue, with 点歌 at the '
      'top and no mode bar', (tester) async {
    final semantics = tester.ensureSemantics();
    final (rooms: _, :router, :settle) = await enterRoom(tester, size: _tablet);
    final play = find.bySemanticsLabel('暂停本机播放');
    final queue = find.text('等待中 1 首');

    expect(play, findsOneWidget);
    expect(find.bySemanticsLabel('投票切歌'), findsOneWidget);
    expect(queue, findsOneWidget);
    expect(
      tester.getRect(queue).left,
      greaterThan(tester.getRect(play).right),
      reason: 'the queue is in a column of its own beside the player',
    );
    expect(
      tester.getRect(find.byTooltip('搜歌')).bottom,
      lessThan(tester.getRect(play).top),
      reason: '点歌 is in the bar at the top',
    );
    // 队列和聊天只在右栏出现一次，歌词留在左栏的播放器下方。
    expect(find.bySemanticsLabel('歌词'), findsNothing);
    expect(find.text('队列'), findsOneWidget);
    expect(find.text('聊天'), findsOneWidget);
    await _expectAccessible(tester);

    await tester.tap(find.text('聊天'));
    await settle();

    expect(router.state.uri.path, '/r/listen/chat');
    expect(find.bySemanticsLabel('说点什么…'), findsOneWidget);
    expect(queue, findsNothing);
    expect(play, findsOneWidget);
    await _expectAccessible(tester);
    semantics.dispose();
  });

  testWidgets('on a tablet the queue and the chat swipe into each other, and '
      'the switch follows once the page settles', (tester) async {
    final (rooms: _, :router, :settle) = await enterRoom(tester, size: _tablet);
    final play = find.bySemanticsLabel('暂停本机播放');
    final before = tester.getRect(play);
    RoomMode switched() => tester
        .widget<SegmentedPills<RoomMode>>(find.byType(SegmentedPills<RoomMode>))
        .selected;

    await tester.drag(find.text('等待中 1 首'), const Offset(-300, 0));
    await settle();
    expect(router.state.uri.path, '/r/listen/chat');
    expect(find.bySemanticsLabel('说点什么…'), findsOneWidget);
    expect(find.text('等待中 1 首'), findsNothing);
    expect(switched(), RoomMode.chat);
    expect(tester.getRect(play), before, reason: 'the player stays');

    await tester.drag(find.text('还没有消息'), const Offset(300, 0));
    await settle();
    expect(router.state.uri.path, '/r/listen/queue');
    expect(find.text('等待中 1 首'), findsOneWidget);
    expect(switched(), RoomMode.queue);
  });

  testWidgets('on a tablet leaving the room while the queue still springs to '
      'the chat is not undone', (tester) async {
    final semantics = tester.ensureSemantics();
    final (rooms: _, :router, :settle) = await enterRoom(tester, size: _tablet);

    await tester.drag(find.text('等待中 1 首'), const Offset(-300, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.state.uri.path, '/r/listen', reason: 'springing');
    await tester.tap(find.bySemanticsLabel('收起房间'));
    await settle();
    await settle();

    expect(router.state.uri.path, '/');
    semantics.dispose();
  });

  testWidgets('on a tablet the keyboard lifts only the chat, and the player '
      'stays where it was', (tester) async {
    final semantics = tester.ensureSemantics();
    final size = _tablets.currentValue!;
    final (rooms: _, :router, :settle) = await enterRoom(tester, size: size);
    router.go('/r/listen/chat');
    await settle();
    final cover = find.byWidgetPredicate(
      (widget) => widget is Hero && widget.tag == 'cover-${testQueueEntry.id}',
    );
    final play = find.bySemanticsLabel('暂停本机播放');
    final before = (tester.getRect(cover), tester.getRect(play));

    // 键盘升起途中和完全升起时各检查一次。
    for (final keyboard in const [100.0, 300.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
      await settle();

      expect(
        (tester.getRect(cover), tester.getRect(play)),
        before,
        reason: 'keyboard $keyboard',
      );
      expect(
        tester.getRect(find.bySemanticsLabel('说点什么…')).bottom,
        lessThanOrEqualTo(size.height - keyboard),
        reason: 'keyboard $keyboard',
      );
    }
    semantics.dispose();
  }, variant: _tablets);

  testWidgets('on a short tablet the keyboard leaves the chat its input and '
      'takes the queue and chat switch away until it goes down', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const size = Size(900, 500);
    final (rooms: _, :router, :settle) = await enterRoom(tester, size: size);
    router.go('/r/listen/chat');
    await settle();
    final queueTab = find.text('队列');
    expect(queueTab, findsOneWidget);
    final input = find.bySemanticsLabel('说点什么…');
    await tester.tap(input);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    const keyboard = 350.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
    await settle();

    expect(tester.takeException(), isNull);
    expect(queueTab, findsNothing);
    expect(input, findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue, reason: 'still typing');
    expect(
      tester.getRect(input).bottom,
      lessThanOrEqualTo(size.height - keyboard),
    );

    tester.view.viewInsets = FakeViewPadding.zero;
    await settle();
    expect(queueTab, findsOneWidget);
    semantics.dispose();
  });

  testWidgets('turning or unfolding between phone and tablet sizes keeps the '
      'room connected and its track playing', (tester) async {
    final semantics = tester.ensureSemantics();
    final engine = FakeAudioEngine();
    final (:rooms, router: _, :settle) = await enterRoom(
      tester,
      engine: engine,
      serverNow: testNowPlaying.startedAtMs + 30000,
    );
    final loads = engine.loadCalls;
    expect(loads, greaterThan(0));

    for (final size in const [
      _tablet,
      Size(1366, 1024),
      Size(700, 1000),
      Size(360, 780),
    ]) {
      tester.view.physicalSize = size * 3;
      await settle();

      expect(rooms.transports, hasLength(1), reason: '$size');
      expect(rooms.last.stopped, isFalse, reason: '$size');
      expect(engine.loadCalls, loads, reason: '$size');
      expect(engine.releaseCalls, 0, reason: '$size');
      expect(find.bySemanticsLabel('暂停本机播放'), findsOneWidget, reason: '$size');
    }
    semantics.dispose();
  });

  testWidgets('wider than a phone, pages keep to a readable width in the '
      'middle', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view
      ..physicalSize = _tablet * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing()],
    );
    final router = appContainer(tester).read(routerProvider);

    for (final page in ['/', '/history', '/settings', '/playlists']) {
      router.go(page);
      await tester.pumpAndSettle();
      final back = page == '/'
          ? find.bySemanticsLabel('设置')
          : find.bySemanticsLabel('返回');
      final edge = (_tablet.width - 640) / 2;
      expect(
        tester.getRect(back).left,
        greaterThanOrEqualTo(edge),
        reason: page,
      );
      expect(
        tester.getRect(back).right,
        lessThanOrEqualTo(_tablet.width - edge),
        reason: page,
      );
    }

    semantics.dispose();
  });

  testWidgets('between phone and tablet widths, the room keeps the phone '
      'layout in the middle', (tester) async {
    final semantics = tester.ensureSemantics();
    await enterRoom(tester, size: const Size(760, 1000));
    final lyrics = find.bySemanticsLabel('歌词');

    expect(lyrics, findsOneWidget);
    expect(tester.getRect(lyrics).left, greaterThan((760 - 640) / 2));
    expect(tester.getRect(find.byTooltip('搜歌')).right, lessThan(760 - 60));
    semantics.dispose();
  });

  testWidgets('on a landscape iPad the room keeps the player on the left and '
      'switches lyrics, queue, and chat in the right pane', (tester) async {
    final semantics = tester.ensureSemantics();
    final size = _landscapeIpads.currentValue!;
    final (rooms: _, :router, :settle) = await enterRoom(tester, size: size);

    final player = tester.getRect(find.byType(NowPlayingHeader));
    final lyrics = tester.getRect(find.byType(LyricsView));

    expect(player.right, lessThanOrEqualTo(lyrics.left));
    expect(
      player.height,
      greaterThan(player.width),
      reason: 'the player stays vertical on the left',
    );
    expect(
      lyrics.height,
      greaterThan(size.height * 0.6),
      reason: 'the right pane spans full height beside the player',
    );
    expect(find.text('歌词'), findsOneWidget);
    expect(find.text('队列'), findsOneWidget);
    expect(find.text('聊天'), findsOneWidget);
    expect(find.byTooltip('搜歌'), findsOneWidget);
    expect(find.byTooltip('从歌单点歌'), findsOneWidget);
    expect(
      tester.getSize(find.byType(SegmentedPills<RoomMode>)).width,
      lessThanOrEqualTo(300),
      reason: 'the mode switcher keeps a compact width instead of stretching',
    );
    await _expectAccessible(tester);

    await tester.tap(find.text('队列'));
    await settle();
    expect(router.state.uri.path, '/r/listen/queue');
    expect(find.text('等待中 1 首'), findsOneWidget);
    expect(tester.getRect(find.byType(NowPlayingHeader)), player);

    await tester.tap(find.text('聊天'));
    await settle();
    expect(router.state.uri.path, '/r/listen/chat');
    expect(find.bySemanticsLabel('说点什么…'), findsOneWidget);
    expect(tester.getRect(find.byType(NowPlayingHeader)), player);

    await tester.tap(find.text('歌词'));
    await settle();
    expect(router.state.uri.path, '/r/listen/lyrics');
    expect(find.byType(LyricsView), findsOneWidget);
    await _expectAccessible(tester);
    semantics.dispose();
  }, variant: _landscapeIpads);

  testWidgets('on a landscape iPad swiping the right pane moves across '
      'lyrics, queue, and chat while the player stays put', (tester) async {
    final (rooms: _, :router, :settle) = await enterRoom(
      tester,
      size: _ipadLandscape,
    );
    final playerBefore = tester.getRect(find.byType(NowPlayingHeader));
    RoomMode switched() => tester
        .widget<SegmentedPills<RoomMode>>(find.byType(SegmentedPills<RoomMode>))
        .selected;

    expect(switched(), RoomMode.lyrics);

    await tester.drag(find.byType(LyricsView), const Offset(-400, 0));
    await settle();
    expect(router.state.uri.path, '/r/listen/queue');
    expect(switched(), RoomMode.queue);
    expect(find.text('等待中 1 首'), findsOneWidget);
    expect(tester.getRect(find.byType(NowPlayingHeader)), playerBefore);

    await tester.drag(find.text('等待中 1 首'), const Offset(-400, 0));
    await settle();
    expect(router.state.uri.path, '/r/listen/chat');
    expect(switched(), RoomMode.chat);
    expect(find.bySemanticsLabel('说点什么…'), findsOneWidget);
    expect(tester.getRect(find.byType(NowPlayingHeader)), playerBefore);
  });

  testWidgets('rotating between portrait and landscape tablet keeps the '
      'selected queue tab aligned without reloading audio', (tester) async {
    final engine = FakeAudioEngine();
    final (:rooms, :router, :settle) = await enterRoom(
      tester,
      size: _tablet,
      engine: engine,
      serverNow: testNowPlaying.startedAtMs + 30000,
    );
    final loads = engine.loadCalls;

    router.go('/r/listen/queue');
    await settle();
    expect(find.text('等待中 1 首'), findsOneWidget);

    tester.view.physicalSize = _ipadLandscape * 3;
    await settle();

    expect(find.text('等待中 1 首'), findsOneWidget);
    expect(find.text('歌词'), findsOneWidget);
    expect(rooms.transports, hasLength(1));
    expect(engine.loadCalls, loads);

    tester.view.physicalSize = _tablet * 3;
    await settle();

    expect(find.text('等待中 1 首'), findsOneWidget);
    expect(find.byType(LyricsView), findsOneWidget);
    expect(rooms.transports, hasLength(1));
    expect(engine.loadCalls, loads);
  });

  testWidgets('landscape iPad layout adapts cleanly at 2x text scale', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await enterRoom(
      tester,
      size: const Size(1024, 768),
      system: const MediaQueryData(textScaler: TextScaler.linear(2)),
    );

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('搜歌'), findsOneWidget);
    expect(find.text('歌词'), findsOneWidget);
    await _expectAccessible(tester);
    semantics.dispose();
  });
}
