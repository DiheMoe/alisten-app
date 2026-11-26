import 'dart:async';

import 'package:alisten/app/desktop/desktop_room.dart';
import 'package:alisten/app/desktop/desktop_room_shell.dart';
import 'package:alisten/app/desktop/desktop_room_transport.dart';
import 'package:alisten/app/mini_player.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/chat/index.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/lyrics/presentation/render_lyric_line.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/flowing_cover_backdrop.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:alisten/shared/ui/zoom_frame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/room/room_fixtures.dart';
import '../../features/lobby/lobby_test_doubles.dart';
import '../../features/room/room_test_doubles.dart';
import '../../features/search/search_test_doubles.dart';
import '../app_test_harness.dart';

const _wideDesktop = Size(1600, 900);

void main() {
  test('Windows typography configures Microsoft YaHei UI fallback', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(
      AlistenTypography.body.fontFamilyFallback,
      contains('Microsoft YaHei UI'),
    );
    expect(
      AlistenTypography.lyric.fontFamilyFallback,
      contains('Microsoft YaHei UI'),
    );
    final theme = buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark));
    expect(
      theme.textTheme.bodyMedium?.fontFamilyFallback,
      contains('Microsoft YaHei UI'),
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(AlistenTypography.body.fontFamilyFallback, isNull);
  });

  testWidgets(
    'desktop room hides cover and lyrics scrollbar, tracks splitter 1:1, '
    'and keeps refreshing while unfocused',
    (tester) async {
      final (:settle, rooms: _, router: _) = await enterRoom(
        tester,
        size: _wideDesktop,
        overrides: [
          lyricsProvider.overrideWithValue(const [
            LyricLine(timeMs: 0, text: '第一行歌词'),
            LyricLine(timeMs: 5000, text: '第二行歌词'),
          ]),
        ],
      );

      // 房间名在页面顶上，封面在歌词左边；歌词页没有滚动条。
      expect(
        find.descendant(
          of: find.byType(DesktopRoomStage),
          matching: find.text('一起听'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .getRect(
              find.descendant(
                of: find.byType(DesktopRoomStage),
                matching: find.byType(CoverArt),
              ),
            )
            .right,
        lessThan(tester.getRect(find.byType(LyricsView)).left),
      );
      expect(find.byType(LyricsView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(LyricsView),
          matching: find.byType(Scrollbar),
        ),
        findsNothing,
      );

      // 分隔条与指针 1:1 对应。
      final queueFinder = find.byType(QueueView);
      final chatFinder = find.byType(ChatView);
      final splitter = find.byKey(
        const ValueKey('desktop-room-panel-splitter'),
      );
      expect(splitter, findsOneWidget);

      final initialQueueHeight = tester.getSize(queueFinder).height;
      final initialChatHeight = tester.getSize(chatFinder).height;
      final start = tester.getCenter(splitter);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();
      expect(
        tester.getSize(queueFinder).height,
        closeTo(initialQueueHeight + 100, 0.5),
      );
      expect(
        tester.getSize(chatFinder).height,
        closeTo(initialChatHeight - 100, 0.5),
      );

      // 拖过极限时两边保持最小可用高度。
      await gesture.moveBy(const Offset(0, -1000));
      await tester.pump();
      expect(
        tester.getSize(queueFinder).height,
        closeTo(DesktopRoomPanel.minPaneHeight, 0.5),
      );
      expect(
        tester.getSize(chatFinder).height,
        greaterThanOrEqualTo(DesktopRoomPanel.minPaneHeight),
      );
      await gesture.up();
      await tester.pump();

      // 双击分隔条恢复默认高度比例。
      final resetCenter = tester.getCenter(splitter);
      await tester.tapAt(resetCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(resetCenter);
      await settle();
      expect(
        tester.getSize(queueFinder).height,
        closeTo(initialQueueHeight, 1.0),
      );

      // 窗口失去焦点（inactive）时仍在屏幕上，照常算在前台；隐藏时才不算。
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      bool visible() => appContainer(tester).read(appVisibleProvider);
      bool ticking() =>
          TickerMode.valuesOf(tester.element(find.byType(LyricsView))).enabled;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(visible(), isTrue);
      expect(ticking(), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(visible(), isFalse);
      expect(ticking(), isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(visible(), isTrue);
      expect(ticking(), isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'the room page fills the window with its own playback controls over the '
    'cover backdrop; other pages are plain, with the sidebar and the mini '
    'player that leads back to the room',
    (tester) async {
      final (:settle, :router, rooms: _) = await enterRoom(
        tester,
        size: _wideDesktop,
      );
      final stage = find.byType(DesktopRoomStage);
      final transport = find.byType(DesktopRoomTransport);

      expect(tester.getRect(stage).left, 0);
      expect(transport, findsOneWidget);
      expect(find.byType(MiniPlayer), findsNothing);
      expect(find.byType(FlowingCoverBackdrop), findsOneWidget);
      expect(find.bySemanticsLabel('我的歌单'), findsNothing);

      router.go('/settings');
      await settle();
      expect(transport, findsNothing);
      expect(find.byType(FlowingCoverBackdrop), findsNothing);
      expect(find.bySemanticsLabel('我的歌单'), findsOneWidget);

      await tester.tap(find.byType(MiniPlayer));
      await settle();
      expect(stage, findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'mouse wheel scrolling unblurs desktop lyrics and resumes after hold',
    (tester) async {
      await enterRoom(
        tester,
        size: _wideDesktop,
        overrides: [
          lyricsProvider.overrideWithValue(const [
            LyricLine(timeMs: 0, text: '第一行歌词'),
            LyricLine(timeMs: 5000, text: '第二行歌词'),
            LyricLine(timeMs: 10000, text: '第三行歌词'),
          ]),
        ],
      );

      final rows = find.byType(LyricLineRow);
      expect(rows, findsNWidgets(3));
      expect(tester.widget<LyricLineRow>(rows.last).scrolling, isFalse);

      // 鼠标滚轮在歌词区域上滚动时立即进入浏览态（解除模糊），3 秒后恢复自动跟随。
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final center = tester.getCenter(find.byType(LyricsView));
      tester.binding.handlePointerEvent(pointer.hover(center));
      tester.binding.handlePointerEvent(pointer.scroll(const Offset(0, 120)));
      await tester.pump();
      expect(tester.widget<LyricLineRow>(rows.last).scrolling, isTrue);

      await tester.pump(const Duration(seconds: 3, milliseconds: 50));
      await tester.pump();
      expect(tester.widget<LyricLineRow>(rows.last).scrolling, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'desktop room right panel collapses smoothly into a right-edge docked '
    'toggle and restores its splitter height on expand',
    (tester) async {
      await enterRoom(tester, size: _wideDesktop);

      final stage = find.byType(DesktopRoomStage);
      final panel = find.byType(DesktopRoomPanel);
      final toggle = find.byKey(const ValueKey('desktop-panel-toggle'));
      final splitter = find.byKey(
        const ValueKey('desktop-room-panel-splitter'),
      );
      final queue = find.byType(QueueView);

      expect(panel, findsOneWidget);
      expect(toggle, findsOneWidget);
      expect(
        find.ancestor(of: toggle, matching: find.byType(Tooltip)),
        findsNothing,
      );

      final expandedStageWidth = tester.getSize(stage).width;
      final panelRect = tester.getRect(panel);
      final toggleExpandedRect = tester.getRect(toggle);
      // 展开态时按钮紧贴右侧面板左边缘并垂直居中。
      expect(toggleExpandedRect.right, closeTo(panelRect.left, 0.5));
      expect(toggleExpandedRect.center.dy, closeTo(panelRect.center.dy, 1.0));

      // 先调整队列高度，确认收起再展开后状态得以保留。
      final initialQueueHeight = tester.getSize(queue).height;
      final drag = await tester.startGesture(
        tester.getCenter(splitter),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(0, 80));
      await tester.pump();
      await drag.up();
      await tester.pump();
      final customQueueHeight = tester.getSize(queue).height;
      expect(customQueueHeight, closeTo(initialQueueHeight + 80, 0.5));

      // 点击收起：中途平滑过渡，结束后面板隐藏且按钮吸附在窗口最右侧中间。
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      final midStageWidth = tester.getSize(stage).width;
      expect(midStageWidth, greaterThan(expandedStageWidth));
      expect(midStageWidth, lessThan(_wideDesktop.width));

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(panel, findsNothing);
      expect(tester.getSize(stage).width, closeTo(_wideDesktop.width, 1));
      final collapsedToggleRect = tester.getRect(toggle);
      expect(collapsedToggleRect.right, closeTo(_wideDesktop.width, 0.5));
      expect(collapsedToggleRect.center.dy, closeTo(panelRect.center.dy, 1.0));

      // 再次点击吸附按钮：平滑展开并保留自定义分隔高度。
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(panel, findsOneWidget);
      expect(tester.getSize(stage).width, closeTo(expandedStageWidth, 1));
      expect(tester.getSize(queue).height, closeTo(customQueueHeight, 0.5));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('the split set by dragging is kept while another page is shown', (
    tester,
  ) async {
    final (:settle, :router, rooms: _) = await enterRoom(
      tester,
      size: _wideDesktop,
    );
    final queue = find.byType(QueueView);
    final initial = tester.getSize(queue).height;
    final drag = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('desktop-room-panel-splitter')),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(0, 80));
    await drag.up();
    await tester.pump();
    expect(tester.getSize(queue).height, closeTo(initial + 80, 0.5));

    router.go('/settings');
    await settle();
    expect(queue, findsNothing);
    router.go('/r/listen');
    await settle();

    expect(tester.getSize(queue).height, closeTo(initial + 80, 0.5));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'the panel is collapsed from the keyboard, and then Tab never lands on '
    'what it hides',
    (tester) async {
      final (:settle, rooms: _, router: _) = await enterRoom(
        tester,
        size: _wideDesktop,
      );
      final toggle = find.byKey(const ValueKey('desktop-panel-toggle'));
      Focus.of(
        tester.element(
          find.descendant(of: toggle, matching: find.byType(Icon)),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settle();
      expect(find.byType(DesktopRoomPanel), findsNothing);

      final panel = tester.element(
        find.byType(DesktopRoomPanel, skipOffstage: false),
      );
      for (var press = 0; press < 40; press++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        var inside = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
          ancestor,
        ) {
          inside = ancestor == panel;
          return !inside;
        });
        expect(inside, isFalse, reason: 'after $press presses of Tab');
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'while the panel slides the lyric lines keep the width they have beside '
    'it, and the edge toggle stays off pages that scroll',
    (tester) async {
      final (:settle, :router, rooms: _) = await enterRoom(
        tester,
        size: const Size(1000, 700),
        overrides: [
          lyricsProvider.overrideWithValue(const [
            LyricLine(timeMs: 0, text: '第一行歌词'),
            LyricLine(timeMs: 5000, text: '第二行歌词'),
          ]),
        ],
      );
      final line = find.byType(LyricLineRow).first;
      final toggle = find.byKey(const ValueKey('desktop-panel-toggle'));
      final beside = tester.getSize(line).width;

      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(tester.getSize(line).width, beside, reason: 'collapsing');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(tester.getSize(line).width, greaterThan(beside));

      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getSize(line).width, beside, reason: 'expanding');
      await tester.pump(const Duration(milliseconds: 500));
      await settle();

      unawaited(router.push<void>('/r/listen/search'));
      await settle();
      await settle();
      expect(toggle, findsNothing);
      expect(find.byType(DesktopRoomPanel), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'with no lyrics, the note that says so stays where it is while the panel '
    'slides away and back',
    (tester) async {
      final (:settle, rooms: _, router: _) = await enterRoom(
        tester,
        size: const Size(1000, 700),
      );
      final toggle = find.byKey(const ValueKey('desktop-panel-toggle'));
      Offset note() => tester.getTopLeft(find.text('暂无歌词'));
      final resting = note();

      await tester.tap(toggle);
      await tester.pump();
      for (final step in const [60, 80, 120, 200]) {
        await tester.pump(Duration(milliseconds: step));
        expect(note(), resting, reason: 'collapsing, after another $step ms');
      }
      await settle();
      expect(note(), resting);

      await tester.tap(toggle);
      await tester.pump();
      for (final step in const [60, 80, 120, 200]) {
        await tester.pump(Duration(milliseconds: step));
        expect(note(), resting, reason: 'expanding, after another $step ms');
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  group('the side buttons of the mouse', () {
    Future<void> press(
      WidgetTester tester,
      int button, {
      Offset at = const Offset(600, 300),
    }) async {
      final pointer = TestPointer(7, PointerDeviceKind.mouse);
      tester.binding.handlePointerEvent(pointer.hover(at));
      tester.binding.handlePointerEvent(pointer.down(at, buttons: button));
      tester.binding.handlePointerEvent(pointer.up());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets(
      'walk back and forward through the pages visited, in the order they '
      'were visited',
      (tester) async {
        final (:settle, :router, rooms: _) = await enterRoom(
          tester,
          size: _wideDesktop,
        );
        String path() => router.state.uri.path;
        router.go('/settings');
        await settle();
        router.go('/history');
        await settle();

        await press(tester, kBackMouseButton);
        expect(path(), '/settings');
        await press(tester, kBackMouseButton);
        expect(path(), '/r/listen');
        await press(tester, kForwardMouseButton);
        expect(path(), '/settings');

        // 走回去之后再去别处，前面那段就没有了。
        router.go('/playlists');
        await settle();
        await press(tester, kForwardMouseButton);
        expect(path(), '/playlists');
        await press(tester, kBackMouseButton);
        expect(path(), '/settings');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets('never lead back into a room that has been left', (
      tester,
    ) async {
      final (:settle, :router, rooms: _) = await enterRoom(
        tester,
        size: _wideDesktop,
      );
      router.go('/settings');
      await settle();
      unawaited(
        appContainer(tester).read(roomControllerProvider.notifier).leaveRoom(),
      );
      await settle();

      await press(tester, kBackMouseButton);

      expect(router.state.uri.path, '/');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('close a dialog before leaving the page under it', (
      tester,
    ) async {
      final (:settle, :router, rooms: _) = await enterRoom(
        tester,
        size: _wideDesktop,
      );
      await tester.tap(find.bySemanticsLabel('退出房间'));
      await settle();
      expect(find.text('退出这个房间？'), findsOneWidget);

      // 指针停在对话框上：点遮罩本来就会关掉它。
      await press(
        tester,
        kBackMouseButton,
        at: tester.getCenter(find.text('退出这个房间？')),
      );

      expect(find.text('退出这个房间？'), findsNothing);
      expect(router.state.uri.path, '/r/listen');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  testWidgets(
    'the pages for adding songs keep the room backdrop behind them; pages '
    'outside the room have their own ground',
    (tester) async {
      final (:settle, :router, rooms: _) = await enterRoom(
        tester,
        size: _wideDesktop,
      );
      Finder ground(Type page) => find.descendant(
        of: find.byType(page),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox &&
              widget.color ==
                  Theme.of(tester.element(find.byType(page)))
                      .colorScheme
                      .surface,
        ),
      );

      unawaited(router.push<void>('/r/listen/search'));
      await settle();
      await settle();
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(ground(SearchScreen), findsNothing);

      router.go('/settings');
      await settle();
      await settle();
      expect(ground(SettingsScreen), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'the room grows out of the mini player, and the buttons for adding songs '
    'and for the room sit at the far end of its top bar',
    (tester) async {
      final (:settle, :router, rooms: _) = await enterRoom(
        tester,
        size: _wideDesktop,
      );
      final stage = find.byType(DesktopRoomStage);
      final whole = tester.getRect(stage);
      expect(
        tester.getRect(find.bySemanticsLabel('搜歌')).left,
        greaterThan(whole.center.dx),
      );
      expect(
        tester.getRect(find.bySemanticsLabel('退出房间')).right,
        greaterThan(whole.right - 80),
      );

      router.go('/');
      await settle();
      await settle();
      final mini = tester.getRect(find.byType(MiniPlayer));

      await tester.tap(find.byType(MiniPlayer));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final growing = tester.getRect(stage);
      expect(growing.width, lessThan(whole.width));
      expect(growing.center.dy, greaterThan(whole.center.dy));
      expect(growing.overlaps(mini.inflate(200)), isTrue);

      await settle();
      await settle();
      expect(tester.getRect(stage), whole);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'the cover of a picked song flies from the results into the queue',
    (tester) async {
      final (:settle, :router, :rooms) = await enterRoom(
        tester,
        size: _wideDesktop,
      );
      rooms.last.responses
        ..addAll(defaultSearchAnswers())
        ..['queue.add'] = {'entry': entryJson('track-1')};
      router.go('/r/listen/search');
      await settle();
      await tester.enterText(
        find.descendant(
          of: find.byType(SearchScreen),
          matching: find.byType(EditableText),
        ),
        '夜曲',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle();

      Finder coverIn(Type list) => find.descendant(
        of: find.descendant(
          of: find.byType(list),
          matching: find.widgetWithText(TrackRow, 'track-1'),
        ),
        matching: find.byType(CoverArt),
      );
      final flying = find.descendant(
        of: find.byType(FittedBox),
        matching: find.byType(CoverArt),
      );
      final from = tester.getRect(coverIn(SearchScreen));
      expect(flying, findsNothing);

      await tester.tap(find.bySemanticsLabel('点歌《track-1》'));
      await tester.pump();
      rooms.last.emit(
        const RoomEventReceived(
          QueueUpdatedEvent(
            term: 1,
            seq: 2,
            pending: null,
            items: [
              QueueEntry(
                id: 'entry-track-1',
                track: Track(source: TrackSource.netease, id: 'track-1'),
                meta: TrackMeta(
                  title: 'track-1',
                  artist: 'artist',
                  album: 'album',
                  coverUrl: '',
                  pageUrl: '',
                  durationMs: 1000,
                ),
                requestedBy: null,
                auto: false,
                likes: 0,
                status: QueueEntryStatus.ready,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 120));
      final to = tester.getRect(coverIn(QueueView));
      expect(to.left, greaterThan(from.right));
      expect(flying, findsOneWidget);
      final midway = tester.getRect(flying).center;
      expect(midway.dx, greaterThan(from.center.dx));
      expect(midway.dx, lessThan(to.center.dx));

      await settle();
      expect(flying, findsNothing);
      expect(tester.getRect(coverIn(SearchScreen)), from);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'saving the playing song sits beside its title, not in the transport',
    (tester) async {
      await enterRoom(tester, size: _wideDesktop);
      final save = find.bySemanticsLabel(RegExp('保存到歌单'));
      expect(save, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DesktopRoomTransport),
          matching: find.byType(SaveToPlaylistButton),
        ),
        findsNothing,
      );
      final stage = find.byType(DesktopRoomStage);
      final cover = tester.getRect(
        find.descendant(of: stage, matching: find.byType(CoverArt)),
      );
      final button = tester.getRect(
        find.descendant(of: stage, matching: find.byType(SaveToPlaylistButton)),
      );
      expect(button.top, greaterThan(cover.bottom));
      expect(button.right, closeTo(cover.right, 12));
      expect(button.top, lessThan(cover.bottom + 80));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'the mini player also offers the vote to skip, and a vote cast in the '
    'room still shows there',
    (tester) async {
      final (:settle, :router, :rooms) = await enterRoom(
        tester,
        size: _wideDesktop,
      );
      rooms.last.responses['playback.voteSkip'] = {
        'votes': 1,
        'required': 2,
        'skipped': false,
      };
      await tester.tap(
        find.descendant(
          of: find.byType(DesktopRoomTransport),
          matching: find.bySemanticsLabel('投票切歌'),
        ),
      );
      await settle();
      expect(
        rooms.last.requests.where(
          (request) => request['type'] == 'playback.voteSkip',
        ),
        hasLength(1),
      );

      router.go('/');
      await settle();
      await settle();
      final vote = find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.bySemanticsLabel('投票切歌'),
      );
      expect(vote, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.bySemanticsLabel('暂停本机播放'),
        ),
        findsOneWidget,
      );
      expect(tester.getSemantics(vote), isSemantics(value: '已投 1/2'));

      // 每次播放只能投一票。
      await tester.tap(vote, warnIfMissed: false);
      await settle();
      expect(
        rooms.last.requests.where(
          (request) => request['type'] == 'playback.voteSkip',
        ),
        hasLength(1),
      );
      expect(router.state.uri.path, '/');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'the panel slides away at its own size, without shrinking its text',
    (tester) async {
      await enterRoom(tester, size: _wideDesktop);
      final panel = find.byType(DesktopRoomPanel);
      final resting = tester.getRect(panel);

      await tester.tap(find.bySemanticsLabel('收起队列与聊天'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final sliding = tester.getRect(panel);
      expect(sliding.size, resting.size);
      expect(sliding.left, greaterThan(resting.left));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('on a large window the cover and the lyrics are larger', (
    tester,
  ) async {
    await enterRoom(tester, size: const Size(2400, 1350));
    final stage = find.byType(DesktopRoomStage);
    final cover = tester.getSize(
      find.descendant(of: stage, matching: find.byType(CoverArt)),
    );
    expect(cover.width, greaterThan(360));
    final lyrics = tester.element(find.byType(LyricsView));
    expect(MediaQuery.textScalerOf(lyrics).scale(10), greaterThan(11));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('when the song changes the title fades to the next one', (
    tester,
  ) async {
    final (settle: _, router: _, :rooms) = await enterRoom(
      tester,
      size: _wideDesktop,
    );
    final stage = find.byType(DesktopRoomStage);
    Finder title(String text) =>
        find.descendant(of: stage, matching: find.text(text));
    expect(title('歌曲'), findsOneWidget);

    const next = QueueEntry(
      id: 'entry-next',
      track: Track(source: TrackSource.netease, id: 'next'),
      meta: TrackMeta(
        title: '下一首歌',
        artist: '歌手',
        album: '专辑',
        coverUrl: '',
        pageUrl: '',
        durationMs: 1000,
      ),
      requestedBy: null,
      auto: false,
      likes: 0,
      status: QueueEntryStatus.ready,
    );
    rooms.last.emit(
      const RoomEventReceived(
        PlaybackUpdatedEvent(
          term: 1,
          seq: 2,
          nowPlaying: NowPlaying(
            entry: next,
            mediaUrl: '/media/netease/next',
            startedAtMs: 2000000,
            durationMs: 180000,
            gain: 1,
            lyric: '',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(title('歌曲'), findsOneWidget);
    expect(title('下一首歌'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(title('歌曲'), findsNothing);
    expect(title('下一首歌'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'Alt with the left and right arrows goes back and forward like the '
    'side buttons',
    (tester) async {
      final (:settle, :router, rooms: _) = await enterRoom(
        tester,
        size: _wideDesktop,
      );
      Future<void> altArrow(LogicalKeyboardKey arrow) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(arrow);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await settle();
      }

      await altArrow(LogicalKeyboardKey.arrowLeft);
      expect(router.state.uri.path, '/');
      await altArrow(LogicalKeyboardKey.arrowRight);
      expect(router.state.uri.path, '/r/listen');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('with the splitter focused the arrow keys move it', (
    tester,
  ) async {
    await enterRoom(tester, size: _wideDesktop);
    final splitter = find.byKey(const ValueKey('desktop-room-panel-splitter'));
    final queue = find.byType(QueueView);
    final before = tester.getSize(queue).height;

    Focus.of(tester.element(splitter)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final lower = tester.getSize(queue).height;
    expect(lower, greaterThan(before));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.getSize(queue).height, lessThan(before));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  group('the sidebar', () {
    testWidgets(
      'is a narrow rail of icons without words that still leads to each page',
      (tester) async {
        final (:settle, :router, rooms: _) = await enterRoom(
          tester,
          size: _wideDesktop,
        );
        router.go('/');
        await settle();
        await settle();

        for (final label in ['大厅', '我的歌单', '播放历史', '设置']) {
          final item = find.bySemanticsLabel(label);
          expect(item, findsOneWidget, reason: label);
          expect(tester.getRect(item).right, lessThan(80), reason: label);
          expect(find.text(label), findsNothing, reason: label);
        }
        expect(
          tester.getSemantics(find.bySemanticsLabel('大厅')),
          isSemantics(isSelected: true),
        );

        await tester.tap(find.bySemanticsLabel('播放历史'));
        await settle();
        expect(router.state.uri.path, '/history');
        expect(
          tester.getSemantics(find.bySemanticsLabel('播放历史').first),
          isSemantics(isSelected: true),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets('shows no words when the mouse rests on an item', (
      tester,
    ) async {
      final (:settle, :router, rooms: _) = await enterRoom(
        tester,
        size: _wideDesktop,
      );
      router.go('/');
      await settle();
      await settle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(800, 450));
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(find.bySemanticsLabel('我的歌单')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('我的歌单'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets(
      'shows the member\'s avatar at the size used for people elsewhere',
      (tester) async {
        tester.view
          ..physicalSize = _wideDesktop * 2
          ..devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await pumpAlistenApp(
          tester,
          api: FakeAlistenApi()
            ..me = const Member(id: 'member-id', name: '听众', avatarHash: 'abc'),
          credentials: FakeCredentialStore()..memberToken = 'member-token',
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        final avatar = find.descendant(
          of: find.bySemanticsLabel('设置'),
          matching: find.byType(MemberAvatar),
        );
        expect(tester.getSize(avatar), const Size.square(AlistenSizes.avatar));
        // 没有头像图片时显示名字的首字，而不是一个空圆。
        expect(
          find.descendant(of: avatar, matching: find.text('听')),
          findsOneWidget,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  });

  testWidgets(
    'the buttons at the top of the room show no words under the mouse',
    (tester) async {
      await enterRoom(tester, size: _wideDesktop);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(800, 450));
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(find.bySemanticsLabel('搜歌')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('搜歌'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  group('the room window', () {
    testWidgets(
      'joined while it is still opening, lays out the room only once it has '
      'settled, then fades it in',
      (tester) async {
        tester.view
          ..physicalSize = _wideDesktop * 2
          ..devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final rooms = FakeRoomTransportFactory();
        await pumpAlistenApp(
          tester,
          api: FakeAlistenApi()
            ..rooms = [roomListing(id: testRoomId, slug: 'listen')],
          credentials: FakeCredentialStore()
            ..tickets[testRoomId] = 'saved-ticket',
          rooms: rooms,
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        await tester.tap(find.text('一起听'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 48));
        // 还没连上时没有队列和聊天可显示。
        expect(find.byType(DesktopRoomPanel), findsNothing);
        rooms.last.emitHello(
          testRoomSnapshot().copyWith(
            term: 1,
            seq: 1,
            room: const RoomInfo(
              id: testRoomId,
              name: '一起听',
              description: '',
              kind: RoomKind.ephemeral,
              capacity: 16,
            ),
            nowPlaying: testNowPlaying,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final stage = find.byType(DesktopRoomStage);
        final inside = find.descendant(
          of: stage,
          matching: find.byType(DesktopRoomTransport),
        );
        expect(stage, findsOneWidget);
        expect(inside, findsNothing);
        expect(find.byType(DesktopRoomPanel), findsOneWidget);
        expect(find.byType(QueueView), findsNothing);

        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(inside, findsOneWidget);
        expect(find.byType(QueueView), findsOneWidget);
        double shown() => tester
            .widget<Opacity>(
              find.ancestor(of: inside, matching: find.byType(Opacity)).first,
            )
            .opacity;
        expect(shown(), lessThan(1));
        await tester.pump(const Duration(seconds: 1));
        expect(shown(), 1);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'shrinks into the mini player after a page inside it has shown its own',
      (tester) async {
        final (:settle, :router, rooms: _) = await enterRoom(
          tester,
          size: _wideDesktop,
        );
        final window = find.byType(DesktopRoomShell);
        final whole = tester.getRect(window);

        await tester.tap(find.bySemanticsLabel('搜歌'));
        await settle();
        await settle();
        router.pop();
        await settle();
        await settle();

        await tester.tap(find.bySemanticsLabel('收起房间'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        final shrinking = tester.getRect(window);
        expect(shrinking.width, lessThan(whole.width * 0.9));
        expect(shrinking.center.dy, greaterThan(whole.center.dy + 20));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'grows out of the mini player when it is opened without a click',
      (tester) async {
        final (:settle, :router, rooms: _) = await enterRoom(
          tester,
          size: _wideDesktop,
        );
        final window = find.byType(DesktopRoomShell);
        final whole = tester.getRect(window);
        router.go('/');
        await settle();
        await settle();
        final mini = tester.getRect(find.byType(MiniPlayer));

        router.go('/r/listen');
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final growing = tester.getRect(window);
        expect(growing.width, lessThan(whole.width));
        expect(growing.overlaps(mini.inflate(200)), isTrue);
        expect(growing.center.dy, greaterThan(whole.center.dy));
        // 外框从迷你播放条的圆角长起。
        expect(
          tester
              .widget<ZoomFrame>(
                find.ancestor(of: window, matching: find.byType(ZoomFrame)),
              )
              .fromRadius,
          AlistenRadii.md,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'is drawn from one picture of itself while it grows and shrinks',
      (tester) async {
        final (:settle, router: _, rooms: _) = await enterRoom(
          tester,
          size: _wideDesktop,
        );
        final window = find.byType(DesktopRoomShell);
        bool pictured() => tester
            .widget<SnapshotWidget>(
              find.ancestor(of: window, matching: find.byType(SnapshotWidget)),
            )
            .controller
            .allowSnapshotting;
        await settle();
        expect(pictured(), isFalse);

        await tester.tap(find.bySemanticsLabel('收起房间'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(pictured(), isTrue);
        await settle();
        await settle();

        await tester.tap(find.byType(MiniPlayer));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(pictured(), isTrue);
        await settle();
        await settle();
        expect(pictured(), isFalse);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets('stays put when the mouse drags across it', (tester) async {
      await enterRoom(tester, size: _wideDesktop);
      final window = find.byType(DesktopRoomShell);
      final whole = tester.getRect(window);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(LyricsView)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(120, 0));
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(tester.getRect(window), whole);
      await gesture.up();
      await tester.pump();
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('fades in where it stands when there is nothing to grow from', (
      tester,
    ) async {
      final (:settle, :router, rooms: _) = await enterRoom(
        tester,
        size: _wideDesktop,
      );
      final window = find.byType(DesktopRoomShell);
      final whole = tester.getRect(window);
      router.go('/');
      unawaited(
        appContainer(tester).read(roomControllerProvider.notifier).leaveRoom(),
      );
      await settle();
      await settle();
      expect(find.byType(MiniPlayer), findsNothing);

      router.go('/r/listen');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final arriving = tester.getRect(window);
      expect(arriving.center.dx, closeTo(whole.center.dx, 1));
      expect(arriving.center.dy, closeTo(whole.center.dy, 1));
      expect(arriving.width, lessThan(whole.width));
      expect(
        tester
            .widgetList<Opacity>(
              find.ancestor(of: window, matching: find.byType(Opacity)),
            )
            .any((content) => content.opacity < 1),
        isTrue,
      );
      await settle();
      await settle();
      expect(tester.getRect(window), whole);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}
