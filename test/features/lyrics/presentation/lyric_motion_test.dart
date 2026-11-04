import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/domain/playback/lyric_timing.dart';
import 'package:alisten/features/lyrics/presentation/lyric_motion.dart';
import 'package:flutter_test/flutter_test.dart';

const _spring = LineChangeSpring(dampingRatio: 0.9, responseSeconds: 0.628);

void main() {
  group('LyricFrameClock', () {
    test('a tick tells listeners the position and the time', () {
      final clock = LyricFrameClock();
      addTearDown(clock.dispose);
      var ticks = 0;
      clock.addListener(() => ticks++);

      clock.tick(positionMs: 1200, nowSeconds: 3);

      expect(ticks, 1);
      expect(clock.positionMs, 1200);
      expect(clock.nowSeconds, 3);
    });

    test('it is busy until the last moment anyone asked for', () {
      final clock = LyricFrameClock();
      addTearDown(clock.dispose);
      expect(clock.busy, isFalse);

      clock
        ..tick(positionMs: 0, nowSeconds: 1)
        ..holdUntil(2)
        ..holdUntil(1.5);

      expect(clock.busy, isTrue);
      clock.tick(positionMs: 0, nowSeconds: 2);
      expect(clock.busy, isFalse);
    });
  });

  group('LyricMotion', () {
    test('a shifted row starts where it was and settles at zero', () {
      final motion = LyricMotion()..configure(3);
      addTearDown(motion.dispose);

      motion.shift(delta: (_) => 40, spring: _spring, nowSeconds: 10);

      expect(motion.offsetOf(1), 40);
      expect(motion.active, isTrue);
      motion.advance(12);
      expect(motion.offsetOf(1), 0);
      expect(motion.active, isFalse);
    });

    test('a delayed row holds until its delay has passed', () {
      final motion = LyricMotion()..configure(2);
      addTearDown(motion.dispose);

      motion.shift(
        delta: (_) => 40,
        delay: (row) => row * 0.2,
        spring: _spring,
        nowSeconds: 0,
      );
      motion.advance(0.1);

      expect(motion.offsetOf(1), 40);
      expect(motion.offsetOf(0), lessThan(40));
    });

    test('a shift during a shift adds to where the row is now', () {
      final motion = LyricMotion()..configure(1);
      addTearDown(motion.dispose);

      motion.shift(delta: (_) => 40, spring: _spring, nowSeconds: 0);
      motion.advance(0.1);
      final midway = motion.offsetOf(0);
      motion.shift(delta: (_) => 30, spring: _spring, nowSeconds: 0.1);

      expect(motion.offsetOf(0), closeTo(midway + 30, 0.001));
    });

    test('a shift during a shift keeps the speed of the row', () {
      final motion = LyricMotion()..configure(2);
      addTearDown(motion.dispose);

      motion.shift(
        delta: (row) => row == 0 ? 40 : 0,
        spring: _spring,
        nowSeconds: 0,
      );
      motion.advance(0.1);
      final moving = motion.offsetOf(0);
      motion.shift(delta: (_) => 0, spring: _spring, nowSeconds: 0.1);
      motion.advance(0.11);

      expect(motion.offsetOf(0), lessThan(moving));
    });

    test('a faster clock settles sooner', () {
      final slow = LyricMotion()..configure(1);
      final fast = LyricMotion()..configure(1);
      addTearDown(slow.dispose);
      addTearDown(fast.dispose);

      slow.shift(delta: (_) => 40, spring: _spring, nowSeconds: 0);
      fast.shift(delta: (_) => 40, spring: _spring, speed: 2, nowSeconds: 0);
      slow.advance(0.2);
      fast.advance(0.2);

      expect(fast.offsetOf(0), lessThan(slow.offsetOf(0)));
    });

    test('an open gap keeps the rows after it apart', () {
      final motion = LyricMotion()..configure(3);
      addTearDown(motion.dispose);

      motion.openGap(1, 20);

      expect(motion.offsetOf(0), 0);
      expect(motion.offsetOf(1), 0);
      expect(motion.offsetOf(2), 20);
      expect(motion.extraOf(2), 20);
      motion.openGap(null, 0);
      expect(motion.offsetOf(2), 0);
    });

    test('clear stops every row where it should end', () {
      final motion = LyricMotion()..configure(2);
      addTearDown(motion.dispose);
      motion
        ..shift(delta: (_) => 40, spring: _spring, nowSeconds: 0)
        ..openGap(0, 20)
        ..clear();

      expect(motion.offsetOf(1), 0);
      expect(motion.active, isFalse);
    });

    test('listeners hear each step', () {
      final motion = LyricMotion()..configure(1);
      addTearDown(motion.dispose);
      var steps = 0;
      motion.addListener(() => steps++);

      motion.shift(delta: (_) => 40, spring: _spring, nowSeconds: 0);
      motion.advance(0.1);

      expect(steps, greaterThanOrEqualTo(2));
    });
  });

  test('rows leave later the farther they are, backwards at half the step', () {
    double delay(int row, {required bool forward}) {
      return staggerDelay(row: row, first: 0, last: 9, forward: forward);
    }

    expect(delay(0, forward: true), 0);
    expect(delay(1, forward: true), 0);
    expect(delay(3, forward: true), closeTo(0.1, 1e-9));
    expect(delay(9, forward: false), 0);
    expect(delay(6, forward: false), closeTo(0.05, 1e-9));
    expect(delay(40, forward: true), closeTo(0.4, 1e-9));
  });

  group('glyphMotionAt', () {
    GlyphMotion heldAt(
      int position, {
      LyricWord word = const LyricWord(
        startMs: 1000,
        durationMs: 2000,
        text: '啊',
      ),
      int? released,
      double offset = 0,
    }) {
      return glyphMotionAt(
        positionMs: position,
        word: word,
        emphasis: 1,
        index: 1,
        count: 1,
        lineHeightEm: 1.3,
        offsetFromWordCenter: offset,
        releasedAtMs: released,
      );
    }

    test('an ordinary word rises once it starts and stays up', () {
      const word = LyricWord(startMs: 1000, durationMs: 200, text: '字');
      GlyphMotion at(int position) {
        return glyphMotionAt(
          positionMs: position,
          word: word,
          emphasis: 0,
          index: 1,
          count: 1,
          lineHeightEm: 1.3,
          offsetFromWordCenter: 0,
        );
      }

      expect(at(999).liftEm, 0);
      expect(at(1050).liftEm, inExclusiveRange(0, 0.09));
      expect(at(1250).liftEm, greaterThan(0.09));
      expect(at(9000).liftEm, closeTo(0.12, 0.002));
      expect(at(9000).scale, 1);
      expect(at(9000).glow, 0);
    });

    test('a held glyph rises, then returns to the lift', () {
      expect(heldAt(999).scale, 1);
      expect(heldAt(999).liftEm, 0);
      expect(heldAt(3000).scale, greaterThan(1.05));
      expect(heldAt(3000).scale, lessThanOrEqualTo(1.14));
      expect(heldAt(3000).liftEm, greaterThan(0.12));
      expect(heldAt(3000).liftEm, closeTo(0.16, 0.02));
      expect(heldAt(9000).scale, closeTo(1, 0.001));
      expect(heldAt(9000).liftEm, closeTo(0.12, 0.002));
    });

    test('the same position gives the same motion, so a pause freezes it', () {
      expect(heldAt(2500).scale, heldAt(2500).scale);
      expect(heldAt(2500).liftEm, heldAt(2500).liftEm);
    });

    test('characters of a word start one after another', () {
      const word = LyricWord(startMs: 0, durationMs: 2000, text: '永远');
      double scaleOf(int index) {
        return glyphMotionAt(
          positionMs: 500,
          word: word,
          emphasis: 1,
          index: index,
          count: 2,
          lineHeightEm: 1.3,
          offsetFromWordCenter: 0,
        ).scale;
      }

      expect(scaleOf(1), greaterThan(scaleOf(2)));
    });

    test('a glyph swells outward from the middle of its word', () {
      expect(heldAt(3000, offset: -10).shiftX, lessThan(0));
      expect(heldAt(3000, offset: 10).shiftX, greaterThan(0));
      expect(heldAt(3000).shiftX, 0);
    });

    test('leaving the line sends a held glyph back early', () {
      const word = LyricWord(startMs: 0, durationMs: 2000, text: '啊');

      expect(heldAt(6000, word: word, released: 1000).scale, closeTo(1, 0.01));
      expect(heldAt(6000, word: word).scale, greaterThan(1));
    });

    test('the glow follows the emphasis and fades after the word', () {
      expect(heldAt(999).glow, 0);
      expect(heldAt(2900).glow, closeTo(0.4, 0.05));
      expect(heldAt(9000).glow, closeTo(0, 0.01));
    });
  });

  group('breakDotsAt', () {
    const gap = LyricBreak(startMs: 0, endMs: 10000);

    test('dots wait a second, then light one by one', () {
      expect(breakDotsAt(gap, 500, smooth: true).lit, [0.1, 0.1, 0.1]);
      final midway = breakDotsAt(gap, 3400, smooth: true).lit;
      expect(midway[0], closeTo(1, 0.001));
      expect(midway[1], closeTo(0.1, 0.001));
      for (final dot in breakDotsAt(gap, 8200, smooth: true).lit) {
        expect(dot, closeTo(1, 1e-9));
      }
    });

    test('dots appear, breathe, and leave before the next line', () {
      expect(breakDotsAt(gap, 0, smooth: true).opacity, 0);
      expect(breakDotsAt(gap, 800, smooth: true).opacity, 1);
      final dots = {
        for (var ms = 1000; ms < 8000; ms += 500)
          breakDotsAt(gap, ms, smooth: true).scale,
      };
      expect(dots.length, greaterThan(3));
      expect(breakDotsAt(gap, 9990, smooth: true).opacity, 0);
      expect(breakDotsAt(gap, 9990, smooth: true).scale, closeTo(0.2, 0.05));
    });

    test('without motion dots only count the time', () {
      final dots = breakDotsAt(gap, 3400, smooth: false);

      expect(dots.scale, 1);
      expect(dots.opacity, 1);
      expect(dots.lit, [1, 0.1, 0.1]);
    });
  });
}
