import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/domain/playback/lyric_timing.dart';
import 'package:alisten/features/lyrics/presentation/lyric_line_layout.dart';
import 'package:alisten/features/lyrics/presentation/lyric_motion.dart';
import 'package:alisten/features/lyrics/presentation/lyric_snapshots.dart';
import 'package:alisten/features/lyrics/presentation/render_lyric_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _styles = LyricTextStyles(
  main: TextStyle(fontSize: 20, height: 1.3, color: Color(0xFFFFFFFF)),
  translation: TextStyle(fontSize: 12, color: Color(0xFFFFFFFF)),
  scaler: TextScaler.noScaling,
);

const _words = LyricLine(
  timeMs: 0,
  endMs: 1000,
  text: '故事',
  words: [
    LyricWord(startMs: 0, durationMs: 500, text: '故'),
    LyricWord(startMs: 500, durationMs: 500, text: '事'),
  ],
);

final class _Rows {
  _Rows(this.clock, this.snapshots);

  final LyricFrameClock clock;
  final LyricSnapshotCache snapshots;
}

Future<_Rows> _setUp(WidgetTester tester) async {
  final rows = _Rows(LyricFrameClock(), LyricSnapshotCache());
  addTearDown(rows.clock.dispose);
  addTearDown(rows.snapshots.clear);
  return rows;
}

Widget _row(
  _Rows rows, {
  LyricLine line = _words,
  LyricBreak? gap,
  LyricLinePhase phase = LyricLinePhase.focused,
  int distance = 0,
  bool scrolling = false,
  bool smooth = true,
  bool prepared = false,
  int index = 0,
}) {
  return RepaintBoundary(
    child: LyricLineRow(
      index: index,
      line: line,
      gap: gap,
      styles: _styles,
      phase: phase,
      distance: distance,
      scrolling: scrolling,
      smooth: smooth,
      clock: rows.clock,
      snapshots: rows.snapshots,
      prepared: prepared,
    ),
  );
}

Widget _column(List<Widget> children) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    ),
  );
}

RenderLyricLine _render(WidgetTester tester, [int at = 0]) {
  return tester.renderObject(find.byType(LyricLineRow).at(at));
}

void main() {
  group('lyricBlurEm', () {
    double blur(LyricLinePhase phase, int distance, {bool scrolling = false}) {
      return lyricBlurEm(
        phase: phase,
        distance: distance,
        scrolling: scrolling,
      );
    }

    test('the current line is sharp', () {
      expect(blur(LyricLinePhase.focused, 0), 0);
    });

    test('lines already sung all share the base radius', () {
      expect(blur(LyricLinePhase.past, 1), closeTo(0.03, 1e-3));
      expect(blur(LyricLinePhase.past, 9), closeTo(0.03, 1e-3));
    });

    test('lines to come blur with their distance, up to the maximum', () {
      expect(blur(LyricLinePhase.upcoming, 1), closeTo(0.02, 1e-3));
      expect(blur(LyricLinePhase.upcoming, 2), closeTo(0.03, 1e-3));
      expect(blur(LyricLinePhase.upcoming, 9), closeTo(0.05, 1e-3));
    });

    test('nothing blurs while the user scrolls', () {
      expect(blur(LyricLinePhase.upcoming, 9, scrolling: true), 0);
      expect(blur(LyricLinePhase.past, 1, scrolling: true), 0);
    });
  });

  group('lyricIdleAlpha', () {
    test('lines dim, and come back while the user scrolls', () {
      expect(lyricIdleAlpha(scrolling: false), 0.3);
      expect(lyricIdleAlpha(scrolling: true), 0.55);
    });
  });

  testWidgets('a word-synced focused line repaints alone as the song moves', (
    tester,
  ) async {
    final rows = await _setUp(tester);
    await tester.pumpWidget(
      _column([
        _row(rows),
        _row(rows, phase: LyricLinePhase.upcoming, distance: 1, index: 1),
      ]),
    );
    final focused = _render(tester).debugPaintCount;
    final idle = _render(tester, 1).debugPaintCount;

    rows.clock.tick(positionMs: 100, nowSeconds: 1);
    await tester.pump();

    expect(_render(tester).debugPaintCount, focused + 1);
    expect(_render(tester, 1).debugPaintCount, idle);
  });

  testWidgets('an idle line settles on a blurred snapshot', (tester) async {
    final rows = await _setUp(tester);
    await tester.pumpWidget(
      _column([_row(rows, phase: LyricLinePhase.past, distance: 2)]),
    );

    expect(_render(tester).debugUsesSnapshot, isTrue);
    expect(_render(tester).debugSelection, 0);
  });

  testWidgets('a scrolled line draws sharp text', (tester) async {
    final rows = await _setUp(tester);
    await tester.pumpWidget(
      _column([
        _row(rows, phase: LyricLinePhase.past, distance: 2, scrolling: true),
      ]),
    );

    expect(_render(tester).debugUsesSnapshot, isFalse);
  });

  testWidgets('leaving focus fades over 400 ms, then settles on a snapshot', (
    tester,
  ) async {
    final rows = await _setUp(tester);
    rows.clock.tick(positionMs: 0, nowSeconds: 10);
    await tester.pumpWidget(_column([_row(rows)]));
    expect(_render(tester).debugSelection, 1);

    await tester.pumpWidget(
      _column([_row(rows, phase: LyricLinePhase.past, distance: 1)]),
    );
    expect(rows.clock.busy, isTrue);
    rows.clock.tick(positionMs: 0, nowSeconds: 10.2);
    await tester.pump();
    expect(_render(tester).debugSelection, inExclusiveRange(0, 1));
    expect(_render(tester).debugUsesSnapshot, isFalse);

    // 淡出全程都是清晰的文字，之后才换成模糊快照。
    rows.clock.tick(positionMs: 0, nowSeconds: 10.39);
    await tester.pump();
    expect(_render(tester).debugUsesSnapshot, isFalse);

    rows.clock.tick(positionMs: 0, nowSeconds: 10.5);
    await tester.pump();
    expect(_render(tester).debugSelection, 0);
    expect(rows.clock.busy, isTrue);

    rows.clock.tick(positionMs: 0, nowSeconds: 10.7);
    await tester.pump();
    expect(_render(tester).debugUsesSnapshot, isTrue);
    expect(rows.clock.busy, isFalse);
  });

  testWidgets('a line keeps its fragments only while it may be sung', (
    tester,
  ) async {
    final rows = await _setUp(tester);
    rows.clock.tick(positionMs: 0, nowSeconds: 10);
    await tester.pumpWidget(_column([_row(rows)]));
    expect(_render(tester).debugHasFragments, isTrue);

    await tester.pumpWidget(
      _column([_row(rows, phase: LyricLinePhase.past, distance: 1)]),
    );
    expect(_render(tester).debugHasFragments, isTrue);

    rows.clock.tick(positionMs: 0, nowSeconds: 10.5);
    await tester.pump();
    expect(_render(tester).debugHasFragments, isFalse);
  });

  testWidgets('the next line builds its fragments ahead of its turn', (
    tester,
  ) async {
    final rows = await _setUp(tester);

    await tester.pumpWidget(
      _column([
        _row(rows, phase: LyricLinePhase.upcoming, distance: 1, prepared: true),
      ]),
    );

    expect(_render(tester).debugHasFragments, isTrue);
  });

  testWidgets('a line far from its turn has no fragments', (tester) async {
    final rows = await _setUp(tester);

    await tester.pumpWidget(
      _column([_row(rows, phase: LyricLinePhase.upcoming, distance: 2)]),
    );

    expect(_render(tester).debugHasFragments, isFalse);
  });

  testWidgets('without motion a line changes state at once', (tester) async {
    final rows = await _setUp(tester);
    rows.clock.tick(positionMs: 0, nowSeconds: 10);
    await tester.pumpWidget(_column([_row(rows, smooth: false)]));

    await tester.pumpWidget(
      _column([
        _row(rows, phase: LyricLinePhase.past, distance: 1, smooth: false),
      ]),
    );

    expect(_render(tester).debugSelection, 0);
    expect(rows.clock.busy, isFalse);
  });

  testWidgets('a line that leaves focus stops listening once it settles', (
    tester,
  ) async {
    final rows = await _setUp(tester);
    await tester.pumpWidget(
      _column([_row(rows, phase: LyricLinePhase.past, distance: 1)]),
    );
    final painted = _render(tester).debugPaintCount;

    rows.clock.tick(positionMs: 100, nowSeconds: 50);
    await tester.pump();

    expect(_render(tester).debugPaintCount, painted);
  });

  testWidgets('a line without a translation takes no room for one', (
    tester,
  ) async {
    final rows = await _setUp(tester);
    await tester.pumpWidget(
      _column([
        _row(rows, line: const LyricLine(timeMs: 0, text: '字')),
        _row(
          rows,
          line: const LyricLine(timeMs: 0, text: '字', translation: 'word'),
          index: 1,
        ),
      ]),
    );

    final plain = _render(tester).size.height;
    final translated = _render(tester, 1).size.height;
    expect(translated, greaterThan(plain));
  });

  testWidgets('a blank line takes no height', (tester) async {
    final rows = await _setUp(tester);
    await tester.pumpWidget(
      _column([_row(rows, line: const LyricLine(timeMs: 0, text: ''))]),
    );

    expect(_render(tester).size.height, 0);
  });

  testWidgets('a break draws its dots only while it is current', (
    tester,
  ) async {
    final rows = await _setUp(tester);
    const blank = LyricLine(timeMs: 0, text: '');
    const gap = LyricBreak(startMs: 0, endMs: 10000);
    rows.clock.tick(positionMs: 2000, nowSeconds: 1);

    await tester.pumpWidget(_column([_row(rows, line: blank, gap: gap)]));
    expect(
      find.byType(LyricLineRow),
      paints
        ..circle()
        ..circle()
        ..circle(),
    );

    await tester.pumpWidget(
      _column([
        _row(
          rows,
          line: blank,
          gap: gap,
          phase: LyricLinePhase.past,
          distance: 1,
          smooth: false,
        ),
      ]),
    );
    expect(find.byType(LyricLineRow), isNot(paints..circle()));
  });

  testWidgets('a focused word line paints each row through a mask', (
    tester,
  ) async {
    final rows = await _setUp(tester);
    rows.clock.tick(positionMs: 250, nowSeconds: 1);

    await tester.pumpWidget(_column([_row(rows)]));

    expect(find.byType(LyricLineRow), paints..rect());
  });

  testWidgets('a line-synced focused line has no mask', (tester) async {
    final rows = await _setUp(tester);

    await tester.pumpWidget(
      _column([_row(rows, line: const LyricLine(timeMs: 0, text: '整行'))]),
    );

    expect(find.byType(LyricLineRow), isNot(paints..rect()));
  });

  testWidgets('a snapshot is kept, and asked for by level', (tester) async {
    final rows = await _setUp(tester);
    await tester.pumpWidget(
      _column([_row(rows, phase: LyricLinePhase.past, distance: 2)]),
    );
    final level = lyricBlurLevel(
      lyricBlurEm(phase: LyricLinePhase.past, distance: 2, scrolling: false),
    );

    final snapshot = rows.snapshots[(0, level)];

    expect(snapshot, isNotNull);
    expect(snapshot!.rect.width, greaterThan(300));
  });

  testWidgets('crossing between two blur levels never shows sharp text', (
    tester,
  ) async {
    final rows = await _setUp(tester);
    rows.clock.tick(positionMs: 0, nowSeconds: 10);
    await tester.pumpWidget(
      _column([_row(rows, phase: LyricLinePhase.upcoming, distance: 2)]),
    );
    await tester.pumpWidget(
      _column([_row(rows, phase: LyricLinePhase.upcoming, distance: 1)]),
    );

    rows.clock.tick(positionMs: 0, nowSeconds: 10.06);
    await tester.pump();

    expect(
      find.byType(LyricLineRow),
      paints
        ..drawImageRect()
        ..drawImageRect(),
    );
  });
}
