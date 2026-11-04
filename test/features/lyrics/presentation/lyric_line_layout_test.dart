import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/features/lyrics/presentation/lyric_line_layout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

LyricLine _line(List<(int, int, String)> words) {
  return LyricLine(
    timeMs: words.first.$1,
    endMs: words.last.$1 + words.last.$2,
    text: words.map((word) => word.$3).join(),
    words: [
      for (final (start, duration, text) in words)
        LyricWord(startMs: start, durationMs: duration, text: text),
    ],
  );
}

const _styles = LyricTextStyles(
  main: TextStyle(fontSize: 20, height: 1.3, color: Color(0xFFFFFFFF)),
  translation: TextStyle(fontSize: 12, color: Color(0xFFFFFFFF)),
  scaler: TextScaler.noScaling,
);

LyricLineLayout _layout(LyricLine line, {double width = 300}) {
  final layout = LyricLineLayout(line, _styles, width);
  addTearDown(layout.dispose);
  return layout;
}

void main() {
  test('words on one row sit where the whole line put them', () {
    final row = _layout(_line([(0, 100, '故'), (100, 100, '事')])).rows.single;

    expect(row.fragments, hasLength(2));
    expect(row.fragments[0].offset.dx, closeTo(0, 0.01));
    expect(row.fragments[1].offset.dx, closeTo(20, 0.01));
    expect(row.rect.left, closeTo(0, 0.01));
    expect(row.rect.right, closeTo(40, 0.01));
  });

  test('a fragment sits on the baseline of its row', () {
    final layout = _layout(_line([(0, 100, '故'), (100, 100, '事')]));
    final row = layout.rows.single;
    final fragment = row.fragments.first;

    expect(
      fragment.offset.dy +
          fragment.painter.computeDistanceToActualBaseline(
            TextBaseline.alphabetic,
          ),
      closeTo(row.baseline, 0.01),
    );
  });

  test('a line too wide for a row breaks into rows', () {
    final layout = _layout(
      _line([for (var i = 0; i < 6; i++) (i * 100, 100, '字')]),
      width: 60,
    );

    expect(layout.rows, hasLength(2));
    expect(layout.rows[0].fragments, hasLength(3));
    expect(layout.rows[1].fragments, hasLength(3));
    expect(layout.rows[1].rect.top, greaterThan(layout.rows[0].rect.top));
    expect(layout.rows[1].steps.first.startMs, 300);
  });

  test('a word longer than a row splits across rows, keeping its spaces and '
      'its time', () {
    const text = 'aaaaa bbbbb ccccc ddddd';
    final layout = _layout(_line([(0, 1000, text)]), width: 60);

    expect(layout.rows.length, greaterThan(1));
    expect(layout.rows.first.steps.single.startMs, 0);
    expect(layout.rows.last.steps.single.endMs, 1000);
    expect(
      layout.rows.expand((row) => row.fragments).map((f) => f.text).join(),
      text,
    );
    for (var row = 1; row < layout.rows.length; row++) {
      expect(
        layout.rows[row].steps.single.startMs,
        layout.rows[row - 1].steps.single.endMs,
      );
    }
  });

  test('a held word splits into its characters', () {
    final fragments = _layout(_line([(0, 2000, '永远')])).rows.single.fragments;

    expect(fragments.map((f) => f.text), ['永', '远']);
    expect(fragments.map((f) => (f.index, f.count)), [(1, 2), (2, 2)]);
    expect(fragments.first.emphasis, 1);
    expect(fragments.first.glow, isNotNull);
    expect(fragments.first.wordCenterX, closeTo(20, 0.01));
    expect(fragments.first.centerX, closeTo(10, 0.01));
    expect(fragments.last.centerX, closeTo(30, 0.01));
  });

  test('a held word keeps a combined character whole', () {
    final fragments = _layout(_line([(0, 2000, 'éa')])).rows.single.fragments;

    expect(fragments.map((f) => f.text), ['é', 'a']);
  });

  test('spaces of a held word draw nothing and count for nothing', () {
    final fragments = _layout(_line([(0, 2000, 'ah '), (2000, 100, 'b')]))
        .rows
        .single
        .fragments;

    expect(fragments.map((f) => f.text), ['a', 'h', 'b']);
    expect(fragments.take(2).map((f) => f.count), [2, 2]);
  });

  test('a short word stays whole and has no glow', () {
    final fragment = _layout(_line([(0, 500, '永远')]))
        .rows
        .single
        .fragments
        .single;

    expect(fragment.text, '永远');
    expect(fragment.emphasis, 0);
    expect(fragment.glow, isNull);
  });

  test('the edge walks the row and waits between words', () {
    final row = _layout(_line([(0, 100, '故'), (500, 100, '事')])).rows.single;

    expect(row.edgeAt(-1), row.rect.left);
    expect(row.edgeAt(0), row.rect.left);
    expect(row.edgeAt(50), closeTo(10, 0.01));
    expect(row.edgeAt(300), closeTo(20, 0.01));
    expect(row.edgeAt(600), closeTo(40, 0.01));
    expect(row.edgeAt(9000), closeTo(40, 0.01));
  });

  test('without sweeping, the edge jumps to the end of each word as it '
      'starts', () {
    final row = _layout(_line([(0, 100, '故'), (500, 100, '事')])).rows.single;

    expect(row.steppedEdgeAt(0), row.rect.left);
    expect(row.steppedEdgeAt(1), closeTo(20, 0.01));
    expect(row.steppedEdgeAt(499), closeTo(20, 0.01));
    expect(row.steppedEdgeAt(501), closeTo(40, 0.01));
  });

  test('a line without word timings has no rows', () {
    final layout = _layout(const LyricLine(timeMs: 0, text: '整行'));

    expect(layout.rows, isEmpty);
    expect(layout.height, closeTo(26, 0.01));
  });

  test('a translation takes room below the line', () {
    final plain = _layout(const LyricLine(timeMs: 0, text: '字'));
    final translated = _layout(
      const LyricLine(timeMs: 0, text: '字', translation: 'word'),
    );

    expect(translated.height, greaterThan(plain.height + 12));
    expect(translated.translationOffset.dy, greaterThanOrEqualTo(plain.height));
  });

  test('a blank line takes no room', () {
    expect(_layout(const LyricLine(timeMs: 0, text: '')).height, 0);
  });

  test('em follows the text scale', () {
    const scaled = LyricTextStyles(
      main: TextStyle(fontSize: 20),
      translation: TextStyle(fontSize: 12),
      scaler: TextScaler.linear(1.5),
    );

    expect(scaled.em, 30);
  });
}
