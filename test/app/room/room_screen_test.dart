import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/app/room/room_mode_bar.dart';
import 'package:alisten/app/room/room_screen.dart';
import 'package:alisten/core/protocol/protocol.gen.dart' show RoomRequestTypes;
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/chat/index.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/lyrics/presentation/render_lyric_line.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/playback_progress_bar.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../domain/room/room_fixtures.dart';
import '../../features/playback/playback_test_doubles.dart'
    show FakeAudioEngine;
import '../app_test_harness.dart';

NowPlaying _track(
  String id,
  String title, {
  required int startedAtMs,
  String lyric = '',
}) {
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
    lyric: lyric,
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

  testWidgets('long pressing the song title copies it, and a tap does not', (
    tester,
  ) async {
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
    final (rooms: _, :router, :settle) = await enterRoom(
      tester,
      nowPlaying: _sung,
    );
    router.go('/r/listen/lyrics');
    await settle();
    final title = _inRoom(find.text('夜曲'));

    await tester.tap(title);
    await settle();
    expect(copied, isNull);

    await tester.longPress(title);
    await tester.pump();

    expect(copied, '夜曲');
    expect(find.text('已复制歌名'), findsOneWidget);
    expect(router.state.uri.path, '/r/listen/lyrics');
  });

  testWidgets('a room without a song has no title to copy', (tester) async {
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
    final (:rooms, :router, :settle) = await enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();
    rooms.last.emit(
      const RoomEventReceived(
        PlaybackUpdatedEvent(term: 1, seq: 2, nowPlaying: null),
      ),
    );
    await settle();

    await tester.longPress(_inRoom(find.text('还没有歌，点一首吧')));
    await tester.pump();

    expect(copied, isNull);
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

  testWidgets('song search waits for a tap before raising the keyboard', (
    tester,
  ) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();

    await tester.tap(find.text('点歌'));
    await settle();

    final field = find.descendant(
      of: find.byType(SearchScreen),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(field);
    await tester.pump();

    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('song search rises as a task, with a way to put it back down', (
    tester,
  ) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();

    await tester.tap(find.text('点歌'));
    await settle();

    final route = ModalRoute.of(tester.element(find.byType(SearchScreen)))!;
    expect((route as PageRoute<void>).fullscreenDialog, isTrue);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });

  testWidgets('on Apple platforms song search keeps the back swipe', (
    tester,
  ) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();

    await tester.tap(find.text('点歌'));
    await settle();

    final route = ModalRoute.of(tester.element(find.byType(SearchScreen)))!;
    expect((route as PageRoute<void>).fullscreenDialog, isFalse);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

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

    expect(
      tester.getSize(controls).height,
      moreOrLessEquals(PlayerControls.height, epsilon: 0.01),
    );
    expect(
      tester.getSize(progress).height,
      moreOrLessEquals(PlaybackProgressBar.heightOf(context), epsilon: 0.01),
    );
  }, variant: _playerCases);

  testWidgets('on a tall phone the player spreads out and sits halfway '
      'between the bars, its side controls mirrored around play', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    await enterRoom(tester, size: const Size(376, 896), nowPlaying: _nocturne);
    final stage = tester.getRect(find.byType(NowPlayingHeader));
    final cover = tester.getRect(_cover('entry-a'));
    final title = tester.getRect(
      find.ancestor(of: find.text('夜曲'), matching: find.byType(Column)).first,
    );
    final progress = tester.getRect(find.byType(PlaybackProgressBar));
    final controls = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is PlayerControls && !widget.compact,
      ),
    );

    expect(
      cover.top - stage.top,
      moreOrLessEquals(stage.bottom - controls.bottom, epsilon: 0.5),
    );
    expect(title.top - cover.bottom, greaterThan(AlistenSpacing.xl));
    expect(controls.top - progress.bottom, greaterThan(AlistenSpacing.md));
    expect(
      progress.top - title.bottom,
      moreOrLessEquals(AlistenSpacing.lg, epsilon: 0.01),
    );

    final play = tester.getCenter(find.bySemanticsLabel('暂停本机播放'));
    final volume = tester.getRect(find.bySemanticsLabel('调节本机音量'));
    final vote = tester.getRect(find.bySemanticsLabel('投票切歌'));
    expect(volume.size, vote.size);
    expect((volume.center.dx + vote.center.dx) / 2, moreOrLessEquals(play.dx));
    expect(volume.center.dy, moreOrLessEquals(play.dy));
    expect(find.text('音量'), findsNothing);
    expect(find.text('投票切歌'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a vote counted shows the tally on the button, and says it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (:rooms, router: _, :settle) = await _enterRoom(tester);
    rooms.last.responses['playback.voteSkip'] = {
      'votes': 1,
      'required': 3,
      'skipped': false,
    };

    await tester.tap(find.bySemanticsLabel('投票切歌'));
    await settle();

    expect(find.text('1/3'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('投票切歌')),
      isSemantics(value: '已投 1/3', hasTapAction: false),
    );
    semantics.dispose();
  });

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

  testWidgets('swiping left on the lyrics turns to the queue and its route, '
      'and swiping right on the chat turns back to the queue', (tester) async {
    final (rooms: _, :router, :settle) = await enterRoom(
      tester,
      nowPlaying: _sung,
    );
    router.go('/r/listen/lyrics');
    await settle();

    await tester.drag(_inRoom(_lyric('第一行')), const Offset(-250, 0));
    await settle();
    expect(router.state.uri.path, '/r/listen/queue');
    expect(_inRoom(find.byType(QueueView)), findsOneWidget);
    expect(_inRoom(find.byType(LyricsView)), findsNothing);
    expect(_scrolledPages(tester), 1);

    router.go('/r/listen/chat');
    await settle();
    await tester.drag(_inRoom(find.byType(ChatView)), const Offset(250, 0));
    await settle();
    expect(router.state.uri.path, '/r/listen/queue');
    expect(_inRoom(find.byType(QueueView)), findsOneWidget);
    expect(_inRoom(find.byType(ChatView)), findsNothing);
  });

  testWidgets('the lyrics do not move right of the first page, nor the chat '
      'left of the last', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    for (final (location, type, offset) in [
      ('/r/listen/lyrics', LyricsView, const Offset(120, 0)),
      ('/r/listen/chat', ChatView, const Offset(-120, 0)),
    ]) {
      router.go(location);
      await settle();
      final page = _inRoom(find.byType(type));
      final before = tester.getRect(page);

      final gesture = await tester.startGesture(tester.getCenter(page));
      await gesture.moveBy(offset);
      await tester.pump();
      await gesture.moveBy(offset);
      await tester.pump();
      expect(tester.getRect(page), before, reason: location);

      await gesture.up();
      await settle();
      expect(router.state.uri.path, location);
      expect(tester.getRect(page), before, reason: location);
    }
  });

  testWidgets('tapping 聊天 on the lyrics slides the content past the queue to '
      'the chat without turning back or routing to the queue', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();
    final routes = _routesOf(router);

    await tester.tap(find.text('聊天'));
    final shown = <double>[];
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      shown.add(_scrolledPages(tester)!);
    }

    expect(
      shown.any((page) => page > 0.5 && page < 1.5),
      isTrue,
      reason: '$shown',
    );
    for (var frame = 1; frame < shown.length; frame++) {
      expect(shown[frame], greaterThanOrEqualTo(shown[frame - 1]));
    }
    expect(shown.last, 2);
    expect(routes, isNot(contains('/r/listen/queue')));
    expect(router.state.uri.path, '/r/listen/chat');
  });

  testWidgets('with reduced motion tapping 聊天 on the lyrics shows the chat in '
      'the next frame, with nothing in between', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(
      tester,
      system: const MediaQueryData(disableAnimations: true),
    );
    router.go('/r/listen/lyrics');
    await settle();
    final routes = _routesOf(router);

    await tester.tap(find.text('聊天'));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_scrolledPages(tester), 2, reason: 'frame $frame');
      expect(_inRoom(find.byType(QueueView)), findsNothing);
      expect(_inRoom(find.byType(LyricsView)), findsNothing);
    }
    expect(routes, isNot(contains('/r/listen/queue')));
    expect(router.state.uri.path, '/r/listen/chat');
  });

  testWidgets('a route from elsewhere, or a tab chosen on the player, shows '
      'its page at once without sliding past others', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();

    // 每一帧要么还是原来的画面，要么已是目标页。
    Future<void> expectStraight({
      required double? from,
      required double to,
      required String reason,
    }) async {
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_inRoom(find.byType(QueueView)), findsNothing, reason: reason);
        expect(_scrolledPages(tester), anyOf(from, to), reason: reason);
      }
      expect(_scrolledPages(tester), to, reason: reason);
    }

    router.go('/r/listen/chat');
    await expectStraight(from: 0, to: 2, reason: 'route');

    await tester.tap(find.text('聊天'));
    await settle();
    expect(router.state.uri.path, '/r/listen');
    await tester.tap(find.text('歌词'));
    await settle();
    await tester.tap(find.text('歌词'));
    await settle();
    expect(router.state.uri.path, '/r/listen');

    await tester.tap(find.text('聊天'));
    await expectStraight(from: null, to: 2, reason: 'from the player');
    expect(router.state.uri.path, '/r/listen/chat');
  });

  testWidgets('halfway through a swipe the thumb of the mode bar sits between '
      'two tabs', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();
    final thumb = _thumb(tester);
    final lyrics = _tab(tester, '歌词');
    final queue = _tab(tester, '队列');
    expect(tester.getRect(thumb).left, moreOrLessEquals(lyrics.left));

    final gesture = await tester.startGesture(
      tester.getCenter(_inRoom(find.byType(LyricsView))),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();

    final halfway = tester.getRect(thumb).left;
    final step = queue.left - lyrics.left;
    expect(halfway, greaterThan(lyrics.left + step / 4));
    expect(halfway, lessThan(queue.left - step / 4));
    await gesture.up();
    await settle();
  });

  testWidgets('a sideways drag that starts on a chat message turns the page, '
      'while dragging it down scrolls the chat and a long press selects it', (
    tester,
  ) async {
    final (:rooms, :router, :settle) = await _enterRoom(tester);
    for (var seq = 2; seq < 32; seq++) {
      rooms.last.emit(
        RoomEventReceived(
          ChatMessageEvent(
            term: 1,
            seq: seq,
            member: testMember,
            content: '消息 $seq',
            sentAtMs: 1000000 + seq,
          ),
        ),
      );
    }
    router.go('/r/listen/chat');
    await settle();
    final latest = find.text('消息 31');

    await tester.drag(latest, const Offset(250, 0));
    await settle();
    expect(router.state.uri.path, '/r/listen/queue');

    router.go('/r/listen/chat');
    await settle();
    final older = find.text('消息 25');
    final before = tester.getRect(older).top;
    await tester.drag(older, const Offset(0, 150));
    await tester.pump();
    expect(tester.getRect(older).top, greaterThan(before + 100));
    expect(router.state.uri.path, '/r/listen/chat');
    await settle();

    await tester.longPress(older);
    await settle();
    expect(find.text('全选'), findsOneWidget);
    expect(router.state.uri.path, '/r/listen/chat');
  });

  testWidgets('lyrics scrolling to their line leave a swipe where the finger '
      'holds it', (tester) async {
    final (:rooms, :router, :settle) = await enterRoom(
      tester,
      nowPlaying: _sung,
    );
    router.go('/r/listen/lyrics');
    await settle();

    final gesture = await tester.startGesture(
      tester.getCenter(_inRoom(_lyric('第一行'))),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump();
    final held = _scrolledPages(tester)!;
    expect(held, greaterThan(0.1));

    rooms.last.emit(
      RoomEventReceived(
        PlaybackUpdatedEvent(
          term: 1,
          seq: 2,
          nowPlaying: _track(
            'entry-b',
            '孤勇者',
            startedAtMs: 1240000,
            lyric: '[00:00.00]另一首的第一行\n[00:04.00]另一首的第二行',
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(_lyric('另一首的第一行'), findsOneWidget);
    expect(_scrolledPages(tester), moreOrLessEquals(held));
    await gesture.up();
    await settle();
  });

  testWidgets('leaving the room, going back or opening the player while a '
      'swipe still springs to its page is not undone by the page', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final leave = _leaving.currentValue!;
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();

    await tester.drag(_inRoom(find.byType(LyricsView)), const Offset(-250, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.state.uri.path, '/r/listen/lyrics', reason: 'springing');
    switch (leave) {
      case _Leave.collapse:
        await tester.tap(find.bySemanticsLabel('收起房间'));
      case _Leave.back:
        await tester.binding.handlePopRoute();
      case _Leave.player:
        await tester.tap(find.bySemanticsLabel('返回播放器'));
    }
    await settle();
    await settle();

    expect(router.state.uri.path, leave == _Leave.player ? '/r/listen' : '/');
    semantics.dispose();
  }, variant: _leaving);

  testWidgets('a sideways drag in the focused chat input moves its cursor, '
      'keeps the keyboard and does not turn the page', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/chat');
    await settle();
    final field = find.byType(EditableText);
    await tester.enterText(field, '一二三四五六七八九十');
    await settle();
    final text = tester.widget<EditableText>(field).controller
      ..selection = const TextSelection.collapsed(offset: 2);
    await settle();

    final rect = tester.getRect(field);
    final gesture = await tester.startGesture(
      Offset(rect.left + 4, rect.center.dy),
    );
    for (var step = 0; step < 10; step++) {
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
    }
    await gesture.up();
    await settle();

    expect(router.state.uri.path, '/r/listen/chat');
    expect(text.selection.baseOffset, greaterThan(2));
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('a route from elsewhere while a finger holds the lyrics at '
      'their edge is shown and kept', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();

    final gesture = await tester.startGesture(
      tester.getCenter(_inRoom(find.byType(LyricsView))),
    );
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    router.go('/r/listen/chat');
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(router.state.uri.path, '/r/listen/chat');
    expect(_scrolledPages(tester), 2);
    await gesture.up();
    await settle();
    expect(router.state.uri.path, '/r/listen/chat');
    expect(_scrolledPages(tester), 2);
  });

  testWidgets('tapping 聊天 and then 歌词 in the next frame ends on the '
      'lyrics', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();

    await tester.tap(find.text('聊天'));
    await tester.pump();
    await tester.tap(find.text('歌词'));
    await settle();

    expect(router.state.uri.path, '/r/listen/lyrics');
    expect(_scrolledPages(tester), 0);
  });

  testWidgets('a tab chosen while the content still folds away under the '
      'player shows its page directly', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();
    await tester.tap(find.text('歌词'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(router.state.uri.path, '/r/listen');
    expect(_inRoom(find.byType(LyricsView)), findsOneWidget, reason: 'fading');

    await tester.tap(find.text('聊天'));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_inRoom(find.byType(QueueView)), findsNothing);
      expect(_scrolledPages(tester), anyOf(0, 2));
    }
    expect(_scrolledPages(tester), 2);
    expect(router.state.uri.path, '/r/listen/chat');
  });

  testWidgets('a finger put down on the content sliding to a tab, and lifted '
      'again, leaves content and route on the same page', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();

    await tester.tap(find.text('聊天'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final caught = _scrolledPages(tester)!;
    expect(caught, inExclusiveRange(0, 2));
    final gesture = await tester.startGesture(
      tester.getCenter(_inRoom(find.byType(PageView))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_scrolledPages(tester), moreOrLessEquals(caught), reason: 'held');
    await gesture.up();
    await settle();

    final page = _scrolledPages(tester)!;
    expect(page, page.roundToDouble());
    expect(
      router.state.uri.path,
      const ['/r/listen/lyrics', '/r/listen/queue', '/r/listen/chat'][page
          .round()],
    );
  });

  testWidgets('a sideways drag on the track row turns no page', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();

    await tester.drag(find.text('夜曲'), const Offset(-250, 0));
    await settle();
    expect(router.state.uri.path, '/r/listen/lyrics');
    expect(_scrolledPages(tester), 0);
  });

  testWidgets('a swipe rebuilds neither the room page, the player nor the '
      'mode bar', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/lyrics');
    await settle();
    final rebuilt = <Type>{};
    debugOnRebuildDirtyWidget = (element, _) =>
        rebuilt.add(element.widget.runtimeType);
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    final gesture = await tester.startGesture(
      tester.getCenter(_inRoom(find.byType(LyricsView))),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
    }
    debugOnRebuildDirtyWidget = null;
    expect(_scrolledPages(tester), greaterThan(0.2));
    expect(rebuilt, isNot(contains(RoomScreen)));
    expect(rebuilt, isNot(contains(NowPlayingHeader)));
    expect(rebuilt, isNot(contains(RoomModeBar)));
    await gesture.up();
    await settle();
  });

  testWidgets('a page swiped away is not kept, so a focused chat input lets '
      'the keyboard go', (tester) async {
    final (rooms: _, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/chat');
    await settle();
    await tester.tap(find.byType(EditableText));
    await settle();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.drag(_inRoom(find.text('还没有消息')), const Offset(250, 0));
    await settle();
    expect(router.state.uri.path, '/r/listen/queue');
    expect(find.byType(ChatView, skipOffstage: false), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('a sideways drag that starts on a queue row turns the page, and '
      'the play mode choices still take a tap', (tester) async {
    final (:rooms, :router, :settle) = await _enterRoom(tester);
    router.go('/r/listen/queue');
    await settle();

    await tester.tap(find.text('随机'));
    await settle();
    expect(
      rooms.last.requests.where(
        (request) => request['type'] == RoomRequestTypes.settingsSetPlayMode,
      ),
      hasLength(1),
    );
    expect(router.state.uri.path, '/r/listen/queue');

    await tester.drag(_inRoom(find.text('歌曲')), const Offset(-250, 0));
    await settle();
    expect(router.state.uri.path, '/r/listen/chat');
  });
}

final _sung = _track(
  'entry-a',
  '夜曲',
  startedAtMs: 1000000,
  lyric: '[00:00.00]第一行\n[00:04.00]第二行\n[00:08.00]第三行',
);

enum _Leave { collapse, back, player }

final _leaving = ValueVariant(_Leave.values.toSet());

Finder _lyric(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is LyricLineRow && widget.line.text == text,
  );
}

Finder _inRoom(Finder finder) =>
    find.descendant(of: find.byType(RoomScreen), matching: finder);

/// 模式内容滚过的页数，歌词、队列、聊天依次为 0、1、2；没有模式内容时为 null。
/// 手机布局下每页与屏幕同宽。
double? _scrolledPages(WidgetTester tester) {
  for (final (index, type) in const [LyricsView, QueueView, ChatView].indexed) {
    final page = _inRoom(find.byType(type));
    if (page.evaluate().isEmpty) continue;
    final rect = tester.getRect(page);
    return index - rect.left / rect.width;
  }
  return null;
}

List<String> _routesOf(GoRouter router) {
  final routes = <String>[];
  void record() => routes.add(router.state.uri.path);
  router.routerDelegate.addListener(record);
  addTearDown(() => router.routerDelegate.removeListener(record));
  return routes;
}

Finder _thumb(WidgetTester tester) {
  final fill = AlistenColors.of(tester.element(find.byType(RoomModeBar)))
      .selectedFill;
  return find.descendant(
    of: find.byType(RoomModeBar),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == fill,
    ),
  );
}

Rect _tab(WidgetTester tester, String label) => tester.getRect(
  find
      .ancestor(
        of: find.descendant(
          of: find.byType(RoomModeBar),
          matching: find.text(label),
        ),
        matching: find.byType(Pressable),
      )
      .first,
);

/// 只统计播放器为预知排版而量取文字高度的次数。其他组件本来就会随键盘重建，
/// 不计入。
final class _CountingScaler extends TextScaler {
  const _CountingScaler(this._count);

  final _Count _count;

  @override
  double scale(double fontSize) {
    final trace = StackTrace.current.toString();
    if (trace.contains('now_playing_header.dart') &&
        trace.contains('AlistenTypography.lineHeight')) {
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

/// 竖屏和横屏手机各取一倍和两倍字号，另加最窄的手机两倍字号。
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
