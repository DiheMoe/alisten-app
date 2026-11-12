import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/domain/playback/playback_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startPlan waits for a future start and plays from zero at the start boundary', () {
    final waiting = startPlan(-200, 1000);
    final starting = startPlan(0, 1000);

    expect(waiting.kind, StartPlanKind.wait);
    expect(waiting.delayMs, 200);
    expect(starting.kind, StartPlanKind.play);
    expect(starting.positionMs, 0);
  });

  test('startPlan locates mid-track and treats duration as ended', () {
    final playing = startPlan(400, 1000);
    final ended = startPlan(1000, 1000);

    expect(playing.kind, StartPlanKind.play);
    expect(playing.positionMs, 400);
    expect(ended.kind, StartPlanKind.ended);
  });

  test('drift beyond one second is corrected only on two checks in a row, '
      'and a correction that lands within a second is enough', () {
    var drift = const DriftCorrection();
    int? check(int positionMs, int expectedMs, int nowMs) {
      final result = drift.check(
        positionMs: positionMs,
        expectedMs: expectedMs,
        nowMs: nowMs,
      );
      drift = result.next;
      return result.seekToMs;
    }

    expect(check(10000, 11100, 100000), isNull, reason: 'one check only');
    expect(check(12000, 12500, 102000), isNull, reason: 'recovered by itself');
    expect(check(14000, 15100, 104000), isNull, reason: 'a new first check');
    expect(check(16000, 17100, 106000), 17100);
    // seek 之后要过一阵才出声，落后的这段再 seek 也追不回来。
    expect(check(19000, 19560, 108000), isNull, reason: 'within a second');
    expect(check(21000, 21560, 110000), isNull, reason: 'still within');
  });

  test('a correction that still leaves more than a second is repeated', () {
    var drift = const DriftCorrection();
    int? check(int positionMs, int expectedMs, int nowMs) {
      final result = drift.check(
        positionMs: positionMs,
        expectedMs: expectedMs,
        nowMs: nowMs,
      );
      drift = result.next;
      return result.seekToMs;
    }

    expect(check(10000, 11500, 100000), isNull);
    expect(check(12000, 13500, 102000), 13500);
    expect(check(14000, 15500, 104000), 15500, reason: 'still 1.5 s off');
    expect(check(17000, 17500, 106000), isNull);
  });

  test('corrections are at least the minimum interval apart', () {
    var drift = const DriftCorrection();
    drift = drift.check(positionMs: 0, expectedMs: 5000, nowMs: 10000).next;
    final first = drift.check(positionMs: 0, expectedMs: 5000, nowMs: 10500);
    final second = first.next.check(
      positionMs: 0,
      expectedMs: 6000,
      nowMs: 11000,
    );

    expect(first.seekToMs, 5000);
    expect(second.seekToMs, isNull);
  });

  test('playback identity includes both entry id and start time', () {
    const first = PlaybackIdentity(entryId: 'entry', startedAtMs: 100);
    const same = PlaybackIdentity(entryId: 'entry', startedAtMs: 100);
    const restarted = PlaybackIdentity(entryId: 'entry', startedAtMs: 101);

    expect(first, same);
    expect(first == restarted, isFalse);
  });
}
