import 'package:alisten/features/lyrics/application/lyric_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a clock starts where it is told', () {
    final sample = (LyricClock()..startAt(90000)).advance(90016);

    expect(sample.positionMs, 90016);
    expect(sample.jumped, isFalse);
  });

  test('a track changed while paused and resumed midway is a seek', () {
    final sample = (LyricClock()..startAt(0)).advance(90000);

    expect(sample.positionMs, 90000);
    expect(sample.jumped, isTrue);
  });

  test('a small step back holds the last position', () {
    final clock = LyricClock()..advance(10000);

    final sample = clock.advance(9600);

    expect(sample.positionMs, 10000);
    expect(sample.jumped, isFalse);
  });

  test('a large step back is a seek', () {
    final clock = LyricClock()..advance(10000);

    final sample = clock.advance(9400);

    expect(sample.positionMs, 9400);
    expect(sample.jumped, isTrue);
  });

  test('more than a second forward is a seek, and the next step is not', () {
    final clock = LyricClock()..advance(10000);

    expect(clock.advance(11001).jumped, isTrue);
    expect(clock.advance(11100).jumped, isFalse);
  });

  test('starting again forgets the last position', () {
    final clock = LyricClock()
      ..advance(90000)
      ..startAt(0);

    final sample = clock.advance(0);

    expect(sample.positionMs, 0);
    expect(sample.jumped, isFalse);
  });
}
