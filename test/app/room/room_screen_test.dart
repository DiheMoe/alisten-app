import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/app/room/room_mode_bar.dart';
import 'package:alisten/app/room/room_screen.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/chat/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/playback_progress_bar.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/room/room_fixtures.dart';
import '../../features/playback/playback_test_doubles.dart'
    show FakeAudioEngine;
import '../app_test_harness.dart';

NowPlaying _track(String id, String title, {required int startedAtMs}) {
  return NowPlaying(
    entry: QueueEntry(
      id: id,
      track: Track(source: TrackSource.netease, id: id),
      meta: TrackMeta(
        title: title,
        artist: '歌手',
        album: '专辑',
        coverUrl: 'https://example.com/$id.jpg',
        pageUrl: 'https://example.com/$id',
        durationMs: 240000,
      ),
      requestedBy: testMember,
      auto: false,
      likes: 0,
      status: QueueEntryStatus.ready,
    ),
    mediaUrl: '/media/netease/$id',
    startedAtMs: startedAtMs,
    durationMs: 240000,
    gain: 1,
    lyric: '',
  );
}

final _nocturne = _track('entry-a', '夜曲', startedAtMs: 1000000);
final _lonelyHero = _track('entry-b', '孤勇者', startedAtMs: 1240000);

Finder _coverHero(String entryId) => find.byWidgetPredicate(
  (widget) => widget is Hero && widget.tag == 'cover-$entryId',
);

// 队列中的封面不是 Hero，借此只匹配房间头部的封面。
Finder _cover(String entryId) => find.descendant(
  of: _coverHero(entryId),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is CoverArt && widget.url == 'https://example.com/$entryId.jpg',
  ),
);

Future<EnteredRoom> _enterRoom(
  WidgetTester tester, {
  MediaQueryData system = const MediaQueryData(),
  FakeAudioEngine? engine,
  int? serverNow,
}) {
  return enterRoom(
    tester,
    system: system,
    nowPlaying: _nocturne,
    engine: engine,
    serverNow: serverNow,
  );
}

void main() {
  testWidgets('the next track replaces the title and cover of the last', (
    tester,
  ) async {
    final (:rooms, router: _, :settle) = await _enterRoom(tester);
    expect(find.text('夜曲'), findsOneWidget);
    expect(_cover('entry-a'), findsOneWidget);
    expect(_coverHero('entry-a'), findsOneWidget);

    rooms.last.emit(
      RoomEventReceived(
        PlaybackUpdatedEvent(term: 1, seq: 2, nowPlaying: _lonelyHero),
      ),
    );
    await settle();

    expect(find.text('孤勇者'), findsOneWidget);
    expect(find.text('夜曲'), findsNothing);
    expect(_cover('entry-b'), findsOneWidget);
    expect(_cover('entry-a'), findsNothing);
    expect(_coverHero('entry-b'), findsOneWidget);
    expect(_coverHero('entry-a'), findsNothing);
  });

  testWidgets('a mode keeps one play control under a small cover, and '
      'choosing it again returns to the player', (tester) async {
    final semantics = tester.ensureSemantics();
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    final playControl = find.bySemanticsLabel('暂停本机播放');
    expect(playControl, findsOneWidget);
    expect(find.bySemanticsLabel('投票切歌'), findsOneWidget);
    expect(tester.getSize(_cover('entry-a')).width, greaterThan(200));

    await tester.tap(find.text('队列'));
    await settle();

    expect(router.state.uri.path, '/r/listen/queue');
    expect(find.text('正在播放'), findsOneWidget);
    expect(playControl, findsOneWidget);
    expect(tester.getSize(_cover('entry-a')).width, lessThanOrEqualTo(64));

    await tester.tap(find.text('队列'));
    await settle();

    expect(router.state.uri.path, '/r/listen');
    expect(find.text('正在播放'), findsNothing);
    expect(playControl, findsOneWidget);
    expect(tester.getSize(_cover('entry-a')).width, greaterThan(200));
    semantics.dispose();
  });

  testWidgets('a lost connection shows that it is reconnecting', (
    tester,
  ) async {
    final (:rooms, router: _, :settle) = await _enterRoom(tester);
    expect(find.textContaining('正在重连'), findsNothing);

    rooms.last.disconnect();
    await settle();

    expect(find.textContaining('正在重连'), findsOneWidget);
    expect(find.textContaining('秒后重试'), findsOneWidget);
    unawaited(rooms.last.stop());
  });

  testWidgets('the invite link names the room by its alias, as the website '
      'does, also when the room was opened by its id', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    final host = appContainer(tester).read(deepLinkControllerProvider).host;
    router.go('/r/$testRoomId');
    await settle();

    await tester.tap(find.bySemanticsLabel('更多'));
    await settle();
    await tester.tap(find.text('复制邀请链接'));
    await settle();

    expect(copied, 'https://$host/r/listen');
    expect(find.text('邀请链接已复制'), findsOneWidget);
    expect(find.text('复制邀请链接'), findsNothing, reason: 'the menu closes');
  });

  testWidgets('inviting lives in the more menu, above leaving the room, in '
      'a menu as wide as its longest item', (tester) async {
    final (rooms: _, router: _, :settle) = await _enterRoom(tester);
    expect(find.bySemanticsLabel('邀请'), findsNothing);

    await tester.tap(find.bySemanticsLabel('更多'));
    await settle();

    Rect item(String label) => tester.getRect(
      find.ancestor(of: find.text(label), matching: find.byType(Pressable)),
    );
    final invite = item('复制邀请链接');
    final leave = item('退出房间');
    expect(invite.bottom, lessThanOrEqualTo(leave.top));
    expect(leave.width, invite.width);
    final text = tester.getRect(find.text('复制邀请链接'));
    expect(invite.width, lessThan(text.width * 2));
  });

  testWidgets('the room fits a phone at twice the text size', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(
      tester,
      system: const MediaQueryData(textScaler: TextScaler.linear(2)),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('夜曲'), findsOneWidget);

    router.go('/r/listen/lyrics');
    await settle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('点歌 opens song search above the room, which keeps its mode', (
    tester,
  ) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();

    await tester.tap(find.text('点歌'));
    await settle();
    expect(router.state.uri.path, '/r/listen/search');

    router.pop();
    await settle();
    expect(router.state.uri.path, '/r/listen/lyrics');
  });

  testWidgets('a track that fails here says so, and a tap tries again', (
    tester,
  ) async {
    final engine = FakeAudioEngine();
    final (rooms: _, router: _, :settle) = await _enterRoom(
      tester,
      engine: engine,
      serverNow: _nocturne.startedAtMs + 30000,
    );
    expect(find.textContaining('播放失败'), findsNothing);

    // 播放失败，重新加载时再失败一次。
    engine
      ..loadFailures = 1
      ..fail();
    await settle();
    await settle();

    expect(find.text('播放失败，点按重试'), findsOneWidget);
    await tester.tap(find.text('播放失败，点按重试'));
    await settle();
    expect(find.textContaining('播放失败'), findsNothing);
  });

  testWidgets('a device that cannot play says so in the room and the mini '
      'player, offers no retry or play control, and loads only once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final engine = FakeAudioEngine()
      ..loadFailures = 100
      ..loadError = const AudioUnavailableException();
    final (rooms: _, :router, :settle) = await _enterRoom(
      tester,
      engine: engine,
      serverNow: _nocturne.startedAtMs + 30000,
    );
    await settle();

    const unavailable = '本机无法播放，请重启应用';
    expect(find.text(unavailable), findsOneWidget);
    expect(find.textContaining('重试'), findsNothing);
    for (final control in ['暂停本机播放', '恢复本机播放']) {
      expect(find.bySemanticsLabel(control), findsNothing, reason: control);
    }
    for (final node in find.semantics.byLabel(unavailable).evaluate()) {
      expect(node, isSemantics(isButton: false, hasTapAction: false));
    }
    await tester.tap(find.text(unavailable));
    await settle();
    await settle();
    expect(engine.loadCalls, 1);

    router.go('/');
    await settle();
    for (final control in ['暂停本机播放', '恢复本机播放']) {
      expect(find.bySemanticsLabel(control), findsNothing, reason: control);
    }
    expect(find.bySemanticsLabel(unavailable), findsOneWidget);
    expect(engine.loadCalls, 1);
    semantics.dispose();
  });

  testWidgets('a track still loading says so, also on the play control', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final engine = FakeAudioEngine()
      ..loadDuration = const Duration(seconds: 10);
    await _enterRoom(
      tester,
      engine: engine,
      serverNow: _nocturne.startedAtMs + 30000,
    );

    expect(find.text('加载中'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('暂停本机播放')).value, '加载中');
    await tester.pump(const Duration(seconds: 10));
    semantics.dispose();
  });

  testWidgets('between two tracks the play control says it waits for the '
      'next one, not that it is unavailable', (tester) async {
    final semantics = tester.ensureSemantics();
    await enterRoom(
      tester,
      engine: FakeAudioEngine(),
      serverNow: testNowPlaying.startedAtMs + testNowPlaying.durationMs + 1000,
    );

    expect(find.text('等待下一首'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('本机播放')), findsNothing);
    final waiting = find.semantics.byLabel('等待下一首');
    expect(waiting, findsAny);
    for (final node in waiting.evaluate()) {
      expect(
        node,
        isSemantics(
          label: '等待下一首',
          isButton: false,
          hasEnabledState: false,
          hasTapAction: false,
        ),
      );
    }
    semantics.dispose();
  });

  testWidgets('a track that starts later waits without moving the progress', (
    tester,
  ) async {
    final (rooms: _, router: _, :settle) = await _enterRoom(
      tester,
      engine: FakeAudioEngine(),
      serverNow: _nocturne.startedAtMs - 5000,
    );

    expect(find.text('等待开播'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    await settle();
    await settle();
    expect(find.text('等待开播'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
  });

  testWidgets('an open popover leaves the page readable, tells that its '
      'button is expanded, and back or a tap outside only closes it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    final more = find.bySemanticsLabel('更多');
    final play = find.bySemanticsLabel('暂停本机播放');

    await tester.tap(more);
    await settle();
    expect(find.bySemanticsLabel('退出房间'), findsOneWidget);
    expect(tester.getSemantics(more), isSemantics(isExpanded: true));
    expect(find.bySemanticsLabel('关闭'), findsOneWidget);
    expect(play, findsOneWidget, reason: 'the page stays readable');

    await tester.binding.handlePopRoute();
    await settle();
    expect(find.bySemanticsLabel('退出房间'), findsNothing);
    expect(router.state.uri.path, '/r/listen');
    expect(tester.getSemantics(more), isSemantics(isExpanded: false));

    final volume = find.bySemanticsLabel('调节本机音量');
    await tester.tap(volume);
    await settle();
    expect(find.bySemanticsLabel('本机音量'), findsOneWidget);
    expect(tester.getSemantics(volume), isSemantics(isExpanded: true));

    // 点在播放按钮上也只会收起音量滑块。
    await tester.tapAt(tester.getCenter(play));
    await settle();
    expect(find.bySemanticsLabel('本机音量'), findsNothing);
    expect(play, findsOneWidget);
    semantics.dispose();
  });

  testWidgets('leaving the room shows the page as it was while it slides '
      'away', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/queue');
    await settle();
    Finder inPage(Finder finder) =>
        find.descendant(of: find.byType(RoomScreen), matching: finder);
    final queue = inPage(find.byType(QueueView));
    expect(queue, findsOneWidget);

    await tester.tap(find.bySemanticsLabel('更多'));
    await settle();
    await tester.tap(find.text('退出房间'));
    await settle();
    await tester.tap(find.text('退出房间'));
    // 面板收起之后页面才开始离开。
    for (var frame = 0; router.state.uri.path != '/'; frame++) {
      expect(frame, lessThan(50), reason: 'the page never started to leave');
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 100));

    // 房间已清空，页面仍在滑出：滑出的是退出前那一刻的整页画面，不再构建房间
    // 内容，因此看不到清空后的队列。
    expect(
      appContainer(tester).read(roomControllerProvider).activeRoomId,
      isNull,
    );
    expect(find.byType(RoomScreen), findsOneWidget);
    expect(queue, findsNothing);
    final still = inPage(find.byType(RawImage));
    expect(still, findsOneWidget);
    expect(tester.getSize(still), const Size(360, 780));
    final image = tester.widget<RawImage>(still).image!;
    expect((image.width, image.height), (360 * 3, 780 * 3));

    await settle();
    expect(find.byType(RoomScreen), findsNothing);
  });

  testWidgets('a short screen keeps the player and its controls clear of the '
      'bars', (tester) async {
    final semantics = tester.ensureSemantics();
    final size = _shortScreens.currentValue!;
    tester.view.padding = const FakeViewPadding(top: 90, bottom: 48);
    await enterRoom(tester, size: size, nowPlaying: _nocturne);

    for (final label in ['暂停本机播放', '投票切歌', '调节本机音量']) {
      expectBetween(
        tester,
        find.bySemanticsLabel(label),
        above: find.bySemanticsLabel('收起房间'),
        below: find.bySemanticsLabel('歌词'),
      );
    }
    expect(find.text('夜曲'), findsOneWidget);
    expect(tester.getSize(_cover('entry-a')).width, greaterThan(120));
    semantics.dispose();
  }, variant: _shortScreens);

  testWidgets('at twice the text size a short screen still fits the player, '
      'its title below the top bar, and the chat with its input', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.padding = const FakeViewPadding(top: 90, bottom: 48);
    final (rooms: _, :router, :settle) = await enterRoom(
      tester,
      size: _shortScreens.currentValue!,
      system: const MediaQueryData(textScaler: TextScaler.linear(2)),
      nowPlaying: _nocturne,
    );
    final topBar = find.bySemanticsLabel('收起房间');
    final modeBar = find.bySemanticsLabel('歌词');

    expect(tester.takeException(), isNull);
    for (final label in ['暂停本机播放', '投票切歌', '调节本机音量']) {
      expectBetween(
        tester,
        find.bySemanticsLabel(label),
        above: topBar,
        below: modeBar,
      );
    }
    expect(
      tester.getRect(find.text('夜曲')).top,
      greaterThanOrEqualTo(tester.getRect(topBar).bottom),
    );
    // 两侧放不下完整文字时只显示图标，名称仍由屏幕阅读器读出。
    expect(find.text('投票切歌'), findsNothing);
    expect(find.text('音量'), findsNothing);

    router.go('/r/listen/chat');
    await settle();
    expect(tester.takeException(), isNull);
    // 输入栏可能比聊天区还高，此时贴底显示，仍能点中输入框开始输入。
    final composer = tester.getRect(
      find
          .ancestor(
            of: find.bySemanticsLabel('说点什么…'),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    expect(composer.top, greaterThanOrEqualTo(tester.getRect(topBar).bottom));
    expect(composer.bottom, lessThanOrEqualTo(tester.getRect(modeBar).top));
    final input = tester
        .getRect(find.bySemanticsLabel('说点什么…'))
        .intersect(composer);
    expect(input.height, greaterThan(0));
    await tester.tapAt(input.center);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    semantics.dispose();
  }, variant: _shortScreens);

  testWidgets("the player's estimated heights are the heights it lays out", (
    tester,
  ) async {
    final (size, scale) = _playerCases.currentValue!;
    await enterRoom(
      tester,
      size: size,
      system: MediaQueryData(textScaler: TextScaler.linear(scale)),
      nowPlaying: _nocturne,
    );
    final controls = find.byWidgetPredicate(
      (widget) => widget is PlayerControls && !widget.compact,
    );
    final progress = find.byType(PlaybackProgressBar);
    final context = tester.element(controls);
    final player = tester.widget<PlayerControls>(controls);

    expect(
      tester.getSize(controls).height,
      moreOrLessEquals(
        PlayerControls.heightOf(
          width: tester.getSize(controls).width,
          labelled: player.labelled,
          labels: player.labels!,
        ),
        epsilon: 0.01,
      ),
    );
    expect(
      tester.getSize(progress).height,
      moreOrLessEquals(PlaybackProgressBar.heightOf(context), epsilon: 0.01),
    );
    for (final label
        in find
            .text('投票切歌')
            .evaluate()
            .followedBy(find.text('音量').evaluate())) {
      final paragraph = label.renderObject! as RenderParagraph;
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragraph.size.width + 0.01),
      );
    }
  }, variant: _playerCases);

  testWidgets('the title is placed by its laid out height, exactly the '
      "player's spacing above the progress", (tester) async {
    final scale = _titleScales.currentValue!;
    await enterRoom(
      tester,
      system: MediaQueryData(textScaler: TextScaler.linear(scale)),
      nowPlaying: _nocturne,
    );
    final title = find
        .ancestor(of: find.text('夜曲'), matching: find.byType(Column))
        .first;

    expect(
      tester.getRect(find.byType(PlaybackProgressBar)).top -
          tester.getRect(title).bottom,
      moreOrLessEquals(AlistenSpacing.lg, epsilon: 0.01),
    );
  }, variant: _titleScales);

  testWidgets('a keyboard moving the room measures no player text again, '
      'however many frames it takes', (tester) async {
    final measured = _Count();
    final (rooms: _, :router, :settle) = await enterRoom(
      tester,
      system: MediaQueryData(textScaler: _CountingScaler(measured)),
      nowPlaying: _nocturne,
    );
    expect(measured.value, greaterThan(0), reason: 'measured when shown');

    for (final location in ['/r/listen', '/r/listen/chat']) {
      router.go(location);
      await settle();
      final before = measured.value;

      for (final keyboard in const [60.0, 120.0, 180.0, 240.0, 300.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(measured.value, before, reason: location);
      tester.view.viewInsets = FakeViewPadding.zero;
    }
  });

  testWidgets('a keyboard covers the mode bar before it lifts the chat input, '
      'which moves one way only as the keyboard rises and falls', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    // 与系统一致：被键盘遮住的底部安全区不再计入 padding。
    const nav = 24.0;
    void keyboardAt(double inset) {
      tester.view
        ..viewInsets = FakeViewPadding(bottom: inset * 3)
        ..viewPadding = const FakeViewPadding(bottom: nav * 3)
        ..padding = FakeViewPadding(bottom: math.max(0, nav - inset) * 3);
    }

    keyboardAt(0);
    router.go('/r/listen/chat');
    await settle();
    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final bar = tester.getRect(find.byType(RoomModeBar));
    final barTotal = screen - bar.top;
    expect(barTotal, greaterThan(nav + AlistenSpacing.xxl));
    final input = find.bySemanticsLabel('说点什么…');
    final queueTab = find.semantics.byLabel('队列');
    expect(queueTab, findsOne);

    final rising = [for (var inset = 0.0; inset <= 300; inset += 15) inset];
    final steps = [...rising, ...rising.reversed.skip(1)];
    double? lastInput;
    for (final (index, inset) in steps.indexed) {
      keyboardAt(inset);
      await tester.pump();

      final reason = 'keyboard $inset';
      expect(
        tester.getRect(find.byType(ChatView)).bottom,
        moreOrLessEquals(screen - math.max(inset, barTotal)),
        reason: reason,
      );
      expect(tester.getRect(find.byType(RoomModeBar)), bar, reason: reason);
      expect(
        queueTab,
        inset >= barTotal ? findsNothing : findsOne,
        reason: reason,
      );
      final inputBottom = tester.getRect(input).bottom;
      if (lastInput != null) {
        expect(
          inputBottom,
          index < rising.length
              ? lessThanOrEqualTo(lastInput)
              : greaterThanOrEqualTo(lastInput),
          reason: reason,
        );
      }
      lastInput = inputBottom;
    }

    await tester.tap(find.text('队列'));
    await settle();
    expect(router.state.uri.path, '/r/listen/queue');
    semantics.dispose();
  });

  testWidgets('Tab never reaches the mode bar while the keyboard covers it, '
      'and does again once it shows', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/chat');
    await settle();
    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final barTotal = screen - tester.getRect(find.byType(RoomModeBar)).top;
    // 按 Tab 的次数足以让焦点绕页面多圈。
    Future<bool> tabReachesModeBar() async {
      for (var press = 0; press < 40; press++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused?.findAncestorWidgetOfExactType<RoomModeBar>() != null) {
          return true;
        }
      }
      return false;
    }

    tester.view.viewInsets = FakeViewPadding(bottom: barTotal * 3);
    await tester.pump();
    expect(await tabReachesModeBar(), isFalse, reason: 'covered');

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(await tabReachesModeBar(), isTrue, reason: 'shown');
  });
}

/// 只统计播放器控件取缩放字号的次数，它每次排版文字或估算文字高度都会取一次。
/// 其他组件本来就会随键盘重建，不计入。
final class _CountingScaler extends TextScaler {
  const _CountingScaler(this._count);

  final _Count _count;

  @override
  double scale(double fontSize) {
    if (StackTrace.current.toString().contains('player_controls.dart')) {
      _count.value++;
    }
    return fontSize;
  }

  @override
  double get textScaleFactor => 1;
}

// TextScaler 不可变，计数放在它之外。
final class _Count {
  int value = 0;
}

/// 1.3 倍时字号乘行高不是整数，排版会对行高取整。
final _titleScales = ValueVariant({1.0, 1.3});

/// 竖屏手机两侧控件带文字，横屏手机不带，各取一倍和两倍字号。窄手机在两倍
/// 字号下高度够放文字，宽度却不够。
final _playerCases = ValueVariant({
  for (final size in const [Size(360, 780), Size(780, 360)])
    for (final scale in const [1.0, 2.0]) (size, scale),
  (const Size(320, 760), 2.0),
});

/// 横屏手机，以及翻盖手机接近正方形的外屏。
final _shortScreens = ValueVariant({
  const Size(780, 360),
  const Size(420, 460),
});
