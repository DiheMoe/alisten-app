import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/lyrics/presentation/render_lyric_line.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:flutter/material.dart';
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

NowPlaying _track({
  String id = 'entry-id',
  String lyric = '',
  String? words,
  String? translation,
}) {
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
    lyricWords: words,
    lyricTrans: translation,
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
      lyricsProvider.overrideWith((ref) {
        final track = ref.watch(_trackFixture);
        return buildLyricLines(
          lyric: track?.lyric ?? '',
          words: track?.lyricWords,
          translation: track?.lyricTrans,
        );
      }),
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

Finder _rowOf(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is LyricLineRow && widget.line.text == text,
  );
}

Finder _row(int index) => _rowOf(_text(index));

LyricLineRow _lineOf(WidgetTester tester, String text) {
  return tester.widget<LyricLineRow>(_rowOf(text).first);
}

LyricLinePhase _phaseOf(WidgetTester tester, int index) {
  return _lineOf(tester, _text(index)).phase;
}

double _offsetFromCenter(WidgetTester tester, int index) {
  return (tester.getCenter(_row(index)).dy - _viewportCenter(tester)).abs();
}

double _singleLineHeight(WidgetTester tester) {
  return tester.getSize(_row(1)).height;
}

// 动画由定时器驱动，`pumpAndSettle` 不会等它。
Future<void> _settle(WidgetTester tester) async {
  await _pumpFor(tester, const Duration(seconds: 3));
}

double _scrollOffset(WidgetTester tester) {
  return tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
}

void main() {
  testWidgets('the current line is centred among wrapped lines, as the song '
      'goes on', (tester) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(80)),
      playback: _playingAt(40),
    );
    await _settle(tester);

    final lineHeight = _singleLineHeight(tester);
    expect(_row(40), findsOneWidget);
    expect(_offsetFromCenter(tester, 40), lessThan(lineHeight));

    // 第 52 行会折成多行，且离视口很远。
    _show(container, _playingAt(52));
    await _settle(tester);
    expect(_offsetFromCenter(tester, 52), lessThan(lineHeight));

    _show(container, _playingAt(45));
    await _settle(tester);
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
    await _settle(tester);
    expectFadedByRow(tester, find.byType(LyricsView), top: true, bottom: true);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 75));
    await tester.pump();
    expectFadedByRow(tester, find.byType(LyricsView), top: true, bottom: true);
  });

  testWidgets('the current line is focused and the others know how far away '
      'they are', (tester) async {
    await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(20)),
      playback: _playingAt(10),
    );
    await _settle(tester);

    expect(_phaseOf(tester, 10), LyricLinePhase.focused);
    expect(_lineOf(tester, _text(10)).distance, 0);
    for (final distance in [1, 2, 3]) {
      expect(_phaseOf(tester, 10 - distance), LyricLinePhase.past);
      expect(_phaseOf(tester, 10 + distance), LyricLinePhase.upcoming);
      expect(_lineOf(tester, _text(10 + distance)).distance, distance);
    }
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
    await _settle(tester);

    expect(tester.getSize(_rowOf('')).height, 0);
    // 空行是当前行时，其他行都不是当前行。
    expect(_lineOf(tester, '第一行').phase, LyricLinePhase.past);
    expect(_lineOf(tester, '第三行').phase, LyricLinePhase.upcoming);
    expect(_lineOf(tester, '').phase, LyricLinePhase.focused);
  });

  testWidgets('a drag stops the lyrics from following for three seconds', (
    tester,
  ) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(80)),
      playback: _playingAt(10),
    );
    await _settle(tester);
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
    await _settle(tester);
    expect(_scrollOffset(tester), isNot(dragged));
    expect(_offsetFromCenter(tester, 30), lessThan(lineHeight));

    _show(container, _playingAt(33));
    await _settle(tester);
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
    await _settle(tester);

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
    await _settle(tester);
    expect(_offsetFromCenter(tester, 30), lessThan(_singleLineHeight(tester)));
  });

  testWidgets('the settled line is not followed while the user holds the '
      'lyrics', (tester) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(80)),
      playback: _playingAt(10),
    );
    await _settle(tester);

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
    await _settle(tester);
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
    await _settle(tester);
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
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(_row(2), findsOneWidget);
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
    await _settle(tester);

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
    await _settle(tester);
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
    await _settle(tester);
    // 暂停时打开，暂停位置所在的行就是当前行。
    expect(_phaseOf(tester, 5), LyricLinePhase.focused);

    _show(
      container,
      const LocalPlaybackState(
        status: LocalPlaybackStatus.buffering,
        positionMs: 9 * _lineMs,
      ),
    );
    await _settle(tester);
    expect(_phaseOf(tester, 5), LyricLinePhase.focused);
    expect(_phaseOf(tester, 9), LyricLinePhase.upcoming);

    _show(container, _playingAt(9));
    await _settle(tester);
    expect(_phaseOf(tester, 9), LyricLinePhase.focused);
    expect(_phaseOf(tester, 5), LyricLinePhase.past);
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
    await _settle(tester);

    container.read(_trackFixture.notifier).play(_track(lyric: _lrc(41)));
    await _settle(tester);

    expect(_phaseOf(tester, 5), LyricLinePhase.focused);
    expect(_offsetFromCenter(tester, 5), lessThan(_singleLineHeight(tester)));
  });

  testWidgets('a track that starts anew begins at the top, however the '
      'last one ended', (tester) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(40)),
      playback: _playingAt(30),
    );
    await _settle(tester);
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
    await _settle(tester);

    // 开播前按歌曲开头计算，首行从 0 ms 开始时它就是当前行。
    expect(_phaseOf(tester, 0), LyricLinePhase.focused);
    expect(_offsetFromCenter(tester, 0), lessThan(_singleLineHeight(tester)));

    _show(container, _playingAt(1));
    await _settle(tester);
    expect(_phaseOf(tester, 1), LyricLinePhase.focused);
  });

  testWidgets('a track that starts under a finger on the old lyrics is '
      'followed all the same', (tester) async {
    final container = await _pumpLyrics(
      tester,
      track: _track(lyric: _lrc(40)),
      playback: _playingAt(30),
    );
    await _settle(tester);

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
    await _settle(tester);
    final lineHeight = _singleLineHeight(tester);
    expect(_offsetFromCenter(tester, 5), lessThan(lineHeight));

    _show(container, _playingAt(8));
    await _settle(tester);
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
    await _settle(tester);

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
    await _settle(tester);
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

  group('word lyrics', () {
    const words =
        '[1000,1000](1000,500,0)故(1500,500,0)事\n'
        '[2100,1000](2100,500,0)的(2600,500,0)花';

    LocalPlaybackState playingAt(int positionMs) {
      return LocalPlaybackState(
        status: LocalPlaybackStatus.playing,
        positionMs: positionMs,
      );
    }

    testWidgets('words light without rebuilding the list, and only the '
        'current line repaints', (tester) async {
      final container = await _pumpLyrics(
        tester,
        track: _track(words: words),
        playback: playingAt(1100),
      );
      await _settle(tester);
      final current = tester.renderObject<RenderLyricLine>(_rowOf('故事'));
      final other = tester.renderObject<RenderLyricLine>(_rowOf('的花'));
      final widget = _lineOf(tester, '故事');
      final painted = current.debugPaintCount;
      final otherPainted = other.debugPaintCount;

      _show(container, playingAt(1200));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));

      expect(_lineOf(tester, '故事'), same(widget));
      expect(current.debugPaintCount, greaterThan(painted));
      expect(other.debugPaintCount, otherPainted);
    });

    testWidgets('a paused word line asks for no frames', (tester) async {
      final container = await _pumpLyrics(
        tester,
        track: _track(words: words),
        playback: playingAt(1100),
      );
      await _settle(tester);

      _show(
        container,
        const LocalPlaybackState(
          status: LocalPlaybackStatus.paused,
          positionMs: 1200,
        ),
      );
      await _settle(tester);
      final painted = tester
          .renderObject<RenderLyricLine>(_rowOf('故事'))
          .debugPaintCount;

      await tester.pump(const Duration(seconds: 1));

      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        tester.renderObject<RenderLyricLine>(_rowOf('故事')).debugPaintCount,
        painted,
      );
    });

    testWidgets('frames stop once a line has been sung', (tester) async {
      await _pumpLyrics(
        tester,
        track: _track(words: '[1000,1000](1000,1000,0)字'),
        playback: playingAt(9000),
      );
      await _settle(tester);

      await tester.pump(const Duration(seconds: 1));

      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('before a track starts its position is not the last one', (
      tester,
    ) async {
      final container = await _pumpLyrics(
        tester,
        track: _track(lyric: _lrc(40)),
        playback: _playingAt(30),
      );
      await _settle(tester);

      container
          .read(_trackFixture.notifier)
          .play(_track(id: 'next', words: words));
      _show(
        container,
        const LocalPlaybackState(
          status: LocalPlaybackStatus.loading,
          positionMs: 90000,
        ),
      );
      await _settle(tester);

      expect(_lineOf(tester, '故事').phase, isNot(LyricLinePhase.past));
    });

    testWidgets('a translation is read out with its line', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpLyrics(
        tester,
        track: _track(words: words, translation: '[00:01.00]Story'),
        playback: playingAt(1100),
      );
      await _settle(tester);

      expect(find.bySemanticsLabel('故事\nStory'), findsOneWidget);
      expect(find.bySemanticsLabel('的花'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a gap of three seconds clears the highlight and leaves no '
        'room for dots', (tester) async {
      await _pumpLyrics(
        tester,
        track: _track(words: '[0,1000](0,1000,0)一\n[4000,1000](4000,1000,0)二'),
        playback: playingAt(1500),
      );
      await _settle(tester);

      expect(_lineOf(tester, '一').phase, LyricLinePhase.past);
      expect(_lineOf(tester, '二').phase, LyricLinePhase.upcoming);
      expect(_lineOf(tester, '').gap, isNull);
    });

    testWidgets('a gap of seven seconds opens room for dots, and closes it', (
      tester,
    ) async {
      const gapped = '[0,1000](0,1000,0)一\n[9000,1000](9000,1000,0)二';
      double apart() {
        return tester.getTopLeft(_rowOf('二')).dy -
            tester.getTopLeft(_rowOf('一')).dy;
      }

      final container = await _pumpLyrics(
        tester,
        track: _track(words: gapped),
        playback: playingAt(500),
      );
      await _settle(tester);
      final closed = apart();

      _show(container, playingAt(2000));
      await _settle(tester);
      expect(_lineOf(tester, '').gap, isNotNull);
      expect(apart(), closeTo(closed + 0.83 * 26, 0.5));

      _show(container, playingAt(8900));
      await _settle(tester);
      expect(apart(), closeTo(closed, 0.5));
    });

    testWidgets('the line after a long break comes to the middle', (
      tester,
    ) async {
      final container = await _pumpLyrics(
        tester,
        track: _track(
          words:
              '[0,1000](0,1000,0)一\n[9000,1000](9000,1000,0)二\n'
              '[10500,1000](10500,1000,0)三',
        ),
        playback: playingAt(2000),
      );
      await _settle(tester);

      _show(container, playingAt(8900));
      await _settle(tester);

      final center = tester.getCenter(_rowOf('二')).dy;
      expect(center, closeTo(_viewportCenter(tester), 1));
    });

    testWidgets('dots keep moving between the half-second updates', (
      tester,
    ) async {
      await _pumpLyrics(
        tester,
        track: _track(words: '[0,1000](0,1000,0)一\n[9000,1000](9000,1000,0)二'),
        playback: playingAt(2000),
      );
      await _settle(tester);
      final dots = tester.renderObject<RenderLyricLine>(_rowOf('').first);
      final painted = dots.debugPaintCount;

      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(dots.debugPaintCount, greaterThan(painted + 10));
    });

    testWidgets('a line change repaints only the lines whose look changes', (
      tester,
    ) async {
      final container = await _pumpLyrics(
        tester,
        track: _track(lyric: _lrc(40)),
        playback: _playingAt(20),
      );
      await _settle(tester);
      final far = tester.renderObject<RenderLyricLine>(_row(27));
      final painted = far.debugPaintCount;

      _show(container, _playingAt(21));
      await _settle(tester);

      expect(far.debugPaintCount, painted);
    });

    testWidgets('with the keyboard up the lyrics step instead of sweeping', (
      tester,
    ) async {
      addTearDown(tester.view.resetViewInsets);
      await _pumpLyrics(
        tester,
        track: _track(words: words),
        playback: playingAt(1100),
      );
      await _settle(tester);
      expect(_lineOf(tester, '故事').smooth, isTrue);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pump();

      expect(_lineOf(tester, '故事').smooth, isFalse);
    });

    testWidgets('lines far from the viewport are not painted', (tester) async {
      await _pumpLyrics(
        tester,
        track: _track(lyric: _lrc(80)),
        playback: _playingAt(0),
      );
      await _settle(tester);

      expect(tester.renderObject<RenderLyricLine>(_row(79)).debugPaintCount, 0);
      expect(
        tester.renderObject<RenderLyricLine>(_row(1)).debugPaintCount,
        greaterThan(0),
      );
    });

    testWidgets('a line left while the user holds the lyrics still fades', (
      tester,
    ) async {
      final container = await _pumpLyrics(
        tester,
        track: _track(lyric: _lrc(40)),
        playback: _playingAt(20),
      );
      await _settle(tester);
      await tester.drag(_row(20), const Offset(0, -50));
      await tester.pump();

      _show(container, _playingAt(21));
      await _pumpFor(tester, const Duration(seconds: 1));

      expect(tester.renderObject<RenderLyricLine>(_row(20)).debugSelection, 0);
      expect(tester.renderObject<RenderLyricLine>(_row(21)).debugSelection, 1);
    });

    testWidgets('rows leave one after another, from the top of the viewport', (
      tester,
    ) async {
      final container = await _pumpLyrics(
        tester,
        track: _track(lyric: _lrc(40)),
        playback: _playingAt(20),
      );
      await _settle(tester);
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final rows = [
        for (var index = 0; index < 40; index++)
          if (viewport.contains(tester.getCenter(_row(index)))) index,
      ];
      final top = rows.first;
      final middle = rows[rows.length ~/ 2];
      final topBefore = tester.getTopLeft(_row(top)).dy;
      final middleBefore = tester.getTopLeft(_row(middle)).dy;

      _show(container, _playingAt(21));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 30));

      final topMoved = topBefore - tester.getTopLeft(_row(top)).dy;
      final middleMoved = middleBefore - tester.getTopLeft(_row(middle)).dy;
      expect(topMoved, greaterThan(0));
      expect(middleMoved, lessThan(topMoved));
    });

    testWidgets('while the user holds the lyrics nothing blurs, and it comes '
        'back after', (tester) async {
      await _pumpLyrics(
        tester,
        track: _track(lyric: _lrc(40)),
        playback: _playingAt(20),
      );
      await _settle(tester);
      expect(_lineOf(tester, _text(21)).scrolling, isFalse);

      await tester.drag(_row(20), const Offset(0, -50));
      await tester.pump();
      expect(_lineOf(tester, _text(21)).scrolling, isTrue);

      await _pumpFor(tester, const Duration(seconds: 5));
      expect(_lineOf(tester, _text(21)).scrolling, isFalse);
    });
  });
}
