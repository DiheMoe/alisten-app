import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../../../shared/ui/edge_fade_probe.dart';

const _lineMs = 3000;

// 每七行中有一行长到会折行。
String _text(int index) {
  return index % 7 == 3 ? '第$index行${'很长的歌词' * 8}' : '第$index行';
}

String _lrc(int count) {
  return [
    for (var index = 0; index < count; index++)
      '[${(index * _lineMs ~/ 60000).toString().padLeft(2, '0')}:'
          '${(index * _lineMs ~/ 1000 % 60).toString().padLeft(2, '0')}.00]'
          '${_text(index)}',
  ].join('\n');
}

NowPlaying _track({String id = 'entry-id', String lyric = ''}) {
  return NowPlaying(
    entry: QueueEntry(
      id: id,
      track: testTrack,
      meta: testTrackMeta,
      requestedBy: testMember,
      auto: false,
      likes: 0,
      status: QueueEntryStatus.ready,
    ),
    mediaUrl: testNowPlaying.mediaUrl,
    startedAtMs: testNowPlaying.startedAtMs,
    durationMs: 600000,
    gain: 1,
    lyric: lyric,
  );
}

final class _Track extends Notifier<NowPlaying?> {
  @override
  NowPlaying? build() => null;

  void play(NowPlaying? track) => state = track;
}

final class _Playback extends Notifier<LocalPlaybackState> {
  @override
  LocalPlaybackState build() => const LocalPlaybackState();

  void show(LocalPlaybackState playback) => state = playback;
}

final _trackFixture = NotifierProvider<_Track, NowPlaying?>(_Track.new);
final _playbackFixture = NotifierProvider<_Playback, LocalPlaybackState>(
  _Playback.new,
);

LocalPlaybackState _playingAt(int index, {int offsetMs = 0}) {
  return LocalPlaybackState(
    status: LocalPlaybackStatus.playing,
    positionMs: index * _lineMs + offsetMs,
  );
}

Future<ProviderContainer> _pumpLyrics(
  WidgetTester tester, {
  NowPlaying? track,
  LocalPlaybackState playback = const LocalPlaybackState(
    status: LocalPlaybackStatus.playing,
  ),
  bool disableAnimations = false,
  Widget Function(Widget lyrics)? around,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(360, 640);
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      nowPlayingProvider.overrideWith((ref) => ref.watch(_trackFixture)),
      lyricsProvider.overrideWith(
        (ref) => parseLrc(ref.watch(_trackFixture)?.lyric ?? ''),
      ),
      playbackControllerProvider.overrideWithBuild(
        (ref, _) => ref.watch(_playbackFixture),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(_trackFixture.notifier).play(track);
  container.read(_playbackFixture.notifier).show(playback);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 640),
        disableAnimations: disableAnimations,
      ),
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Scaffold(
            body: (around ?? (lyrics) => lyrics)(const LyricsView()),
          ),
        ),
      ),
    ),
  );
  return container;
}

void _show(ProviderContainer container, LocalPlaybackState playback) {
  container.read(_playbackFixture.notifier).show(playback);
}

// 运行中的动画只有逐帧推进才会前进。
Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  await tester.pump();
  for (var passed = Duration.zero; passed < duration; passed += _frame) {
    await tester.pump(_frame);
  }
}

const _frame = Duration(milliseconds: 100);

double _viewportCenter(WidgetTester tester) {
  return tester.getCenter(find.byType(SingleChildScrollView)).dy;
}

double _offsetFromCenter(WidgetTester tester, int index) {
  return (tester.getCenter(find.text(_text(index))).dy -
          _viewportCenter(tester))
      .abs();
}

double _singleLineHeight(WidgetTester tester) {
  return tester.getSize(find.text(_text(1))).height;
}

double _scrollOffset(WidgetTester tester) {
  return tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
}

TextStyle _styleOf(WidgetTester tester, String text) {
  return tester.renderObject<RenderParagraph>(find.text(text)).text.style!;
}

double _scaleOf(WidgetTester tester, String text) {
  return tester
      .widget<AnimatedScale>(
        find.ancestor(
          of: find.text(text),
          matching: find.byType(AnimatedScale),
        ),
      )
      .scale;
}

void main() {
  testWidgets('the current line is centred among wrapped lines, as the song '
      'goes on', (tester) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(80)),
      playback: _playingAt(40),
    );
    await tester.pumpAndSettle();

    final lineHeight = _singleLineHeight(tester);
    expect(find.text(_text(40)), findsOneWidget);
    expect(_offsetFromCenter(tester, 40), lessThan(lineHeight));

    // 第 52 行会折成多行，且离视口很远。
    _show(container, _playingAt(52));
    await tester.pumpAndSettle();
    expect(_offsetFromCenter(tester, 52), lessThan(lineHeight));

    _show(container, _playingAt(45));
    await tester.pumpAndSettle();
    expect(_offsetFromCenter(tester, 45), lessThan(lineHeight));
  });

  testWidgets('lines fade row by row into the top and bottom edges', (
    tester,
  ) async {
    await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(40)),
      playback: _playingAt(20),
    );
    await tester.pumpAndSettle();
    expectFadedByRow(tester, find.byType(LyricsView), top: true, bottom: true);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 75));
    await tester.pump();
    expectFadedByRow(tester, find.byType(LyricsView), top: true, bottom: true);
  });

  testWidgets('the current line is emphasised and the others fade with '
      'their distance from it', (tester) async {
    await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(20)),
      playback: _playingAt(10),
    );
    await tester.pumpAndSettle();

    final current = _styleOf(tester, _text(10));
    expect(current.fontWeight!.value, greaterThanOrEqualTo(700));
    expect(current.color!.a, closeTo(1, 0.001));
    expect(
      current.shadows,
      AlistenColors.of(tester.element(find.byType(LyricsView))).glowTextShadows,
    );
    expect(_scaleOf(tester, _text(10)), 1.08);
    expect(
      tester
          .widget<AnimatedScale>(
            find.ancestor(
              of: find.text(_text(10)),
              matching: find.byType(AnimatedScale),
            ),
          )
          .duration,
      AlistenDurations.lyricLine,
    );

    for (final (distance, opacity) in [(1, 0.82), (2, 0.64), (3, 0.46)]) {
      for (final index in [10 - distance, 10 + distance]) {
        final style = _styleOf(tester, _text(index));
        expect(style.color!.a, closeTo(opacity, 0.001), reason: '$index');
        expect(style.fontWeight!.value, lessThan(700), reason: '$index');
        expect(style.shadows ?? const [], isEmpty, reason: '$index');
        expect(_scaleOf(tester, _text(index)), 1, reason: '$index');
      }
    }
    // 1 - 0.18 * 5 低于下限。
    expect(_styleOf(tester, _text(15)).color!.a, closeTo(0.25, 0.001));
    expect(_styleOf(tester, _text(19)).color!.a, closeTo(0.25, 0.001));
  });

  testWidgets('a blank line takes part in the timing without a row of its '
      'own', (tester) async {
    await _pumpLyrics(
      tester,
      track: _track(lyric: '[00:01.00]第一行\n[00:03.00]\n[00:05.00]第三行'),
      playback: const LocalPlaybackState(
        status: LocalPlaybackStatus.playing,
        positionMs: 3500,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(''), findsNothing);
    // 空行是当前行时，其他行都不是当前行。
    for (final text in ['第一行', '第三行']) {
      expect(_styleOf(tester, text).fontWeight!.value, lessThan(700));
      expect(_scaleOf(tester, text), 1);
    }
  });

  testWidgets('a drag stops the lyrics from following for three seconds', (
    tester,
  ) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(80)),
      playback: _playingAt(10),
    );
    await tester.pumpAndSettle();
    final lineHeight = _singleLineHeight(tester);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final dragged = _scrollOffset(tester);

    await tester.pump(const Duration(seconds: 1));
    _show(container, _playingAt(30));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(_scrollOffset(tester), dragged);

    // 拖动三秒后歌词即回到正在唱的行，不等下一行开始。
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), isNot(dragged));
    expect(_offsetFromCenter(tester, 30), lessThan(lineHeight));

    _show(container, _playingAt(33));
    await tester.pumpAndSettle();
    expect(_offsetFromCenter(tester, 33), lessThan(lineHeight));
  });

  testWidgets('lyrics stay under a finger that still holds them', (
    tester,
  ) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(80)),
      playback: _playingAt(10),
    );
    await tester.pumpAndSettle();

    final finger = await tester.startGesture(
      tester.getCenter(find.byType(SingleChildScrollView)),
    );
    await finger.moveBy(const Offset(0, -200));
    await tester.pump();
    final held = _scrollOffset(tester);

    // 已超过拖动后的三秒，但手指还按着。
    _show(container, _playingAt(30));
    await _pumpFor(tester, const Duration(seconds: 4));
    expect(_scrollOffset(tester), held);

    await finger.up();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(_offsetFromCenter(tester, 30), lessThan(_singleLineHeight(tester)));
  });

  testWidgets('the current line is centred again once its transition ends, '
      'however the lines reflowed meanwhile', (tester) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(80)),
      playback: _playingAt(10),
    );
    await tester.pumpAndSettle();

    _show(container, _playingAt(30));
    await _pumpFor(tester, const Duration(milliseconds: 100));
    // 模拟字重变化后各行折行改变造成的偏移。
    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
    await tester.pumpAndSettle();

    expect(_offsetFromCenter(tester, 30), lessThan(_singleLineHeight(tester)));
  });

  testWidgets('the settled line is not followed while the user holds the '
      'lyrics', (tester) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(80)),
      playback: _playingAt(10),
    );
    await tester.pumpAndSettle();

    _show(container, _playingAt(30));
    await _pumpFor(tester, const Duration(milliseconds: 100));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 100));
    await tester.pump();
    final dragged = _scrollOffset(tester);

    await _pumpFor(tester, const Duration(seconds: 1));
    expect(_scrollOffset(tester), dragged);
  });

  testWidgets('position ticks inside a line do not scroll the lyrics', (
    tester,
  ) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(80)),
      playback: _playingAt(10),
    );
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    position.jumpTo(position.pixels + 40);
    await tester.pump();
    final moved = _scrollOffset(tester);

    for (var tick = 1; tick <= 5; tick++) {
      _show(container, _playingAt(10, offsetMs: tick * 500));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(_scrollOffset(tester), moved, reason: 'tick $tick');
    }
    expect(tester.binding.hasScheduledFrame, isFalse);

    _show(container, _playingAt(11));
    await tester.pumpAndSettle();
    expect(_offsetFromCenter(tester, 11), lessThan(_singleLineHeight(tester)));
  });

  testWidgets('lyrics leave the primary scroll controller to the page', (
    tester,
  ) async {
    final primary = ScrollController();
    addTearDown(primary.dispose);

    await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(10)),
      playback: _playingAt(2),
      around: (lyrics) =>
          PrimaryScrollController(controller: primary, child: lyrics),
    );

    expect(primary.hasClients, isFalse);
  });

  testWidgets('lyrics given no height to fill lay out all the same', (
    tester,
  ) async {
    await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(5)),
      playback: _playingAt(2),
      around: (lyrics) =>
          SingleChildScrollView(child: Column(children: [lyrics])),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(_text(2)), findsOneWidget);
    expect(tester.getSize(find.byType(LyricsView)).height.isFinite, isTrue);
  });

  testWidgets('a new drag holds the lyrics again from where it ended', (
    tester,
  ) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(80)),
      playback: _playingAt(10),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    final dragged = _scrollOffset(tester);

    // 此时第一次拖动后的三秒已过，第二次的还没过。
    await tester.pump(const Duration(seconds: 1));
    _show(container, _playingAt(30));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(_scrollOffset(tester), dragged);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), isNot(dragged));
  });

  testWidgets('with animations removed, the lyrics jump to the next line '
      'without animating', (tester) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(80)),
      playback: _playingAt(10),
      disableAnimations: true,
    );
    await tester.pump();
    final lineHeight = _singleLineHeight(tester);
    expect(_offsetFromCenter(tester, 10), lessThan(lineHeight));

    _show(container, _playingAt(52));
    // 一帧构建新的当前行，一帧滚动到它；时间始终没有推进。
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_offsetFromCenter(tester, 52), lessThan(lineHeight));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the lyrics follow the room only while this device plays', (
    tester,
  ) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(40)),
      playback: const LocalPlaybackState(
        status: LocalPlaybackStatus.paused,
        positionMs: 5 * _lineMs,
      ),
    );
    await tester.pumpAndSettle();
    // 暂停时打开，暂停位置所在的行就是当前行。
    expect(_styleOf(tester, _text(5)).fontWeight!.value, greaterThan(600));

    _show(
      container,
      const LocalPlaybackState(
        status: LocalPlaybackStatus.buffering,
        positionMs: 9 * _lineMs,
      ),
    );
    await tester.pumpAndSettle();
    expect(_styleOf(tester, _text(5)).fontWeight!.value, greaterThan(600));
    expect(_styleOf(tester, _text(9)).fontWeight!.value, lessThan(700));

    _show(container, _playingAt(9));
    await tester.pumpAndSettle();
    expect(_styleOf(tester, _text(9)).fontWeight!.value, greaterThan(600));
    expect(_styleOf(tester, _text(5)).fontWeight!.value, lessThan(700));
  });

  testWidgets('another lyric of the same playback keeps the line at the '
      'paused position', (tester) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(40)),
      playback: const LocalPlaybackState(
        status: LocalPlaybackStatus.paused,
        positionMs: 5 * _lineMs,
      ),
    );
    await tester.pumpAndSettle();

    container.read(_trackFixture.notifier).play(_track(lyric: _lrc(41)));
    await tester.pumpAndSettle();

    expect(_scaleOf(tester, _text(5)), 1.08);
    expect(_offsetFromCenter(tester, 5), lessThan(_singleLineHeight(tester)));
  });

  testWidgets('a track that starts anew begins at the top, however the '
      'last one ended', (tester) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(40)),
      playback: _playingAt(30),
    );
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), greaterThan(0));
    final before = tester.state<ScrollableState>(find.byType(Scrollable));

    container
        .read(_trackFixture.notifier)
        .play(_track(id: 'next', lyric: _lrc(40)));
    _show(
      container,
      const LocalPlaybackState(status: LocalPlaybackStatus.loading),
    );
    await tester.pump();
    // 换用新的滚动视图，而不是把旧视图移到顶部，否则会有一帧显示旧偏移。
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)),
      isNot(same(before)),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < 40; index++) {
      if (find.text(_text(index)).evaluate().isEmpty) continue;
      expect(_scaleOf(tester, _text(index)), 1, reason: '$index');
    }
    expect(_offsetFromCenter(tester, 0), lessThan(_singleLineHeight(tester)));

    _show(container, _playingAt(0));
    await tester.pumpAndSettle();
    expect(_scaleOf(tester, _text(0)), 1.08);
  });

  testWidgets('a track that starts under a finger on the old lyrics is '
      'followed all the same', (tester) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(40)),
      playback: _playingAt(30),
    );
    await tester.pumpAndSettle();

    final finger = await tester.startGesture(
      tester.getCenter(find.byType(SingleChildScrollView)),
    );
    await finger.moveBy(const Offset(0, -100));
    await tester.pump();

    // 旧滚动视图在手指仍按着时被移除，永远不会报告拖动结束。
    container
        .read(_trackFixture.notifier)
        .play(_track(id: 'next', lyric: _lrc(40)));
    _show(container, _playingAt(5));
    await tester.pumpAndSettle();
    final lineHeight = _singleLineHeight(tester);
    expect(_offsetFromCenter(tester, 5), lessThan(lineHeight));

    _show(container, _playingAt(8));
    await tester.pumpAndSettle();
    expect(_offsetFromCenter(tester, 8), lessThan(lineHeight));
    await finger.up();
  });

  testWidgets('lyrics that change under a finger on them stay in its hands, '
      'and are held after it lets go', (tester) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(40)),
      playback: _playingAt(30),
    );
    await tester.pumpAndSettle();

    final finger = await tester.startGesture(
      tester.getCenter(find.byType(SingleChildScrollView)),
    );
    await finger.moveBy(const Offset(0, -100));
    await tester.pump();
    final held = _scrollOffset(tester);

    // 同一次播放重新获取了歌词，多出一行。
    container.read(_trackFixture.notifier).play(_track(lyric: _lrc(41)));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(_scrollOffset(tester), held);

    await finger.up();
    _show(container, _playingAt(33));
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(_scrollOffset(tester), held);

    await _pumpFor(tester, const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_offsetFromCenter(tester, 33), lessThan(_singleLineHeight(tester)));
  });

  testWidgets('lyrics are laid out in a repaint boundary of their own', (
    tester,
  ) async {
    await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(10)),
      playback: _playingAt(2),
    );

    expect(
      find.descendant(
        of: find.byType(LyricsView),
        matching: find.ancestor(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(RepaintBoundary),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a track without lyrics says so', (tester) async {
    await _pumpLyrics(tester, track: _track());

    expect(find.text('暂无歌词'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await _pumpLyrics(tester);

    expect(find.text('暂无歌词'), findsOneWidget);
  });
}
