import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/domain/playback/lyric_timing.dart';
import 'package:flutter_test/flutter_test.dart';

const _lrcLines = [
  LyricLine(timeMs: 10000, text: '一'),
  LyricLine(timeMs: 13000, text: '二'),
];

LyricLine _wordLine(int startMs, int endMs) {
  return LyricLine(
    timeMs: startMs,
    endMs: endMs,
    text: '字',
    words: [
      LyricWord(startMs: startMs, durationMs: endMs - startMs, text: '字'),
    ],
  );
}

void main() {
  group('wordEmphasis', () {
    LyricWord word(int durationMs, [String text = '爱']) {
      return LyricWord(startMs: 0, durationMs: durationMs, text: text);
    }

    test('a word of 600 ms or less is not emphasised', () {
      expect(wordEmphasis(word(400)), 0);
      expect(wordEmphasis(word(600)), 0);
    });

    test('a word just past the threshold is already visibly emphasised', () {
      expect(wordEmphasis(word(601)), closeTo(0.35, 0.001));
    });

    test('emphasis grows with the duration and stops at two seconds', () {
      expect(wordEmphasis(word(1300)), closeTo(0.675, 1e-9));
      expect(wordEmphasis(word(2000)), 1);
      expect(wordEmphasis(word(6000)), 1);
    });

    test('long words and blanks are not emphasised, and surrounding spaces '
        'do not count', () {
      expect(wordEmphasis(word(2000, 'Forevers')), 0);
      expect(wordEmphasis(word(2000, 'Forever ')), 1);
      expect(wordEmphasis(word(2000, '  ')), 0);
    });
  });

  group('LyricTimeline', () {
    test('a line-synced lyric moves on half a second before the next line', () {
      final timeline = LyricTimeline(_lrcLines);

      expect(timeline.focusAt(12500), 0);
      expect(timeline.focusAt(12501), 1);
    });

    test('the first line is reached ahead of its time as well', () {
      final timeline = LyricTimeline(_lrcLines);
      final settle = timeline.springInto(0).settleMs;

      expect(timeline.focusAt(10000 - settle - 1), -1);
      expect(timeline.focusAt(10000 - settle), 0);
    });

    test('a word-synced line holds until its last word ends', () {
      final timeline = LyricTimeline([
        _wordLine(0, 2900),
        _wordLine(3000, 6000),
      ]);

      expect(timeline.focusAt(2900), 0);
      expect(timeline.focusAt(2901), 1);
    });

    test('a word-synced line gives way ahead of the next line by the time '
        'the page needs to settle', () {
      final timeline = LyricTimeline([
        _wordLine(0, 1000),
        _wordLine(9000, 10000),
      ]);
      final settle = timeline.springInto(1).settleMs;

      expect(timeline.focusAt(9000 - settle - 1), 0);
      expect(timeline.focusAt(9000 - settle), 1);
    });

    test('a line that overlaps the next gives way when the next begins', () {
      final timeline = LyricTimeline([
        _wordLine(0, 5000),
        _wordLine(3000, 6000),
      ]);

      expect(timeline.focusAt(2999), 0);
      expect(timeline.focusAt(3000), 1);
    });

    test('the line at a position does not depend on how it was reached', () {
      final timeline = LyricTimeline(_lrcLines);

      expect(timeline.focusAt(12600), 1);
      expect(timeline.focusAt(100), -1);
      expect(timeline.focusAt(12600), 1);
    });

    test('a blank line clears the highlight and hands over to the next line '
        'half a second early', () {
      final timeline = LyricTimeline([
        _wordLine(0, 1000),
        const LyricLine(timeMs: 1000, text: ''),
        _wordLine(9000, 10000),
      ]);

      expect(timeline.focusAt(1001), 1);
      expect(timeline.focusAt(8500), 1);
      expect(timeline.focusAt(8501), 2);
    });

    test('nextFocusChangeMs lands where focusAt changes', () {
      final timeline = LyricTimeline([
        _wordLine(0, 1000),
        _wordLine(9000, 10000),
      ]);

      final change = timeline.nextFocusChangeMs(500)!;

      expect(timeline.focusAt(change - 1), 0);
      expect(timeline.focusAt(change), 1);
    });

    test('nextFocusChangeMs waits for a line that was reached early', () {
      final timeline = LyricTimeline(_lrcLines);

      expect(timeline.focusAt(12900), 1);
      expect(timeline.nextFocusChangeMs(12900), isNull);
    });

    test('after a line that was reached early the next change is not in the '
        'past', () {
      final timeline = LyricTimeline([
        _wordLine(0, 100),
        _wordLine(9000, 9100),
        _wordLine(9200, 10000),
      ]);

      expect(timeline.focusAt(8900), 1);
      expect(timeline.nextFocusChangeMs(8900), greaterThanOrEqualTo(9000));
    });

    test('there is no next change after the last line', () {
      final timeline = LyricTimeline(_lrcLines);

      expect(timeline.nextFocusChangeMs(20000), isNull);
    });

    test('the page tightens as the gap between lines shrinks', () {
      LyricTimeline withGap(int gapMs) {
        return LyricTimeline([
          _wordLine(0, 1000),
          _wordLine(1000 + gapMs, 2000 + gapMs),
        ]);
      }

      expect(withGap(200).springInto(1).dampingRatio, closeTo(0.9, 1e-9));
      expect(withGap(200).springInto(1).responseSeconds, closeTo(0.48, 1e-9));
      expect(withGap(750).springInto(1).dampingRatio, closeTo(0.78, 1e-9));
      expect(withGap(750).springInto(1).responseSeconds, closeTo(0.75, 1e-9));
      expect(withGap(5000).springInto(1).dampingRatio, closeTo(0.78, 1e-9));
    });

    test('a line-synced lyric uses one spring', () {
      final spring = LyricTimeline(_lrcLines).springInto(1);

      expect(spring.dampingRatio, 0.9);
      expect(spring.responseSeconds, closeTo(0.628, 1e-9));
      expect(spring.settleMs, inInclusiveRange(760, 775));
    });

    test(
      'a line in a word-synced lyric with no line before it gets no gap',
      () {
        final timeline = LyricTimeline([_wordLine(0, 1000)]);

        expect(timeline.springInto(0).responseSeconds, closeTo(0.48, 1e-9));
      },
    );

    test('a break needs seven seconds and a line after it', () {
      final timeline = LyricTimeline(const [
        LyricLine(timeMs: 0, text: '一'),
        LyricLine(timeMs: 1000, text: ''),
        LyricLine(timeMs: 8000, text: '二'),
        LyricLine(timeMs: 9000, text: ''),
        LyricLine(timeMs: 15999, text: '三'),
        LyricLine(timeMs: 17000, text: ''),
      ]);

      expect(timeline.breakAt(0), isNull);
      expect(timeline.breakAt(1)?.startMs, 1000);
      expect(timeline.breakAt(1)?.endMs, 8000);
      expect(timeline.breakAt(3), isNull);
      expect(timeline.breakAt(5), isNull);
    });

    test('releaseMs of the last line is its own end', () {
      final timeline = LyricTimeline([_wordLine(0, 1000)]);

      expect(timeline.releaseMs(0), 1000);
    });
  });
}
