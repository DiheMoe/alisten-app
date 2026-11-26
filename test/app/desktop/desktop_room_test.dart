import 'dart:async';

import 'package:alisten/app/desktop/desktop_player_bar.dart';
import 'package:alisten/app/desktop/desktop_room.dart';
import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/features/chat/index.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/lyrics/presentation/render_lyric_line.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/playback_progress_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

      // 房间名只在左侧栏的卡片上。
      expect(find.text('一起听'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DesktopRoomStage),
          matching: find.text('一起听'),
        ),
        findsNothing,
      );

      // 舞台上没有大封面，歌词页没有滚动条。
      expect(
        find.descendant(
          of: find.byType(DesktopRoomStage),
          matching: find.byType(CoverArt),
        ),
        findsNothing,
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
    'clicking the bottom-left player bar cover returns to the room and save '
    'button stays anchored on the right',
    (tester) async {
      final (:settle, :router, rooms: _) = await enterRoom(
        tester,
        size: _wideDesktop,
      );

      final bar = find.byType(DesktopPlayerBar);
      final saveButton = find.descendant(
        of: bar,
        matching: find.byType(SaveToPlaylistButton),
      );
      final progress = find.descendant(
        of: bar,
        matching: find.byType(PlaybackProgressBar),
      );
      expect(saveButton, findsOneWidget);
      expect(
        tester.getRect(saveButton).left,
        greaterThan(tester.getRect(progress).right),
      );

      router.go('/settings');
      await settle();
      expect(router.state.uri.path, '/settings');

      final cover = find.descendant(of: bar, matching: find.byType(CoverArt));
      expect(cover, findsOneWidget);
      await tester.tap(cover);
      await settle();
      expect(router.state.uri.path, '/r/listen');
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
      expect(midStageWidth, lessThan(_wideDesktop.width - 208));

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(panel, findsNothing);
      expect(tester.getSize(stage).width, closeTo(_wideDesktop.width - 208, 1));
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
}
