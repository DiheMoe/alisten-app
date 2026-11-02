const playbackDriftCheckIntervalMs = 2000;
const playbackDriftEnterMs = 1000;
const playbackDriftExitMs = 300;
const playbackDriftStrikes = 2;

const playbackMinCorrectionIntervalMs = 2000;

enum StartPlanKind { wait, play, ended }

final class StartPlan {
  const StartPlan._(this.kind, {this.delayMs, this.positionMs});

  final StartPlanKind kind;
  final int? delayMs;
  final int? positionMs;
}

StartPlan startPlan(int expectedMs, int durationMs) {
  if (expectedMs < 0) {
    return StartPlan._(StartPlanKind.wait, delayMs: -expectedMs);
  }
  if (expectedMs >= durationMs) return const StartPlan._(StartPlanKind.ended);
  return StartPlan._(StartPlanKind.play, positionMs: expectedMs);
}

/// 单次超过 [playbackDriftEnterMs] 可能只是会自行恢复的卡顿，
/// 而每次 seek 都听得出来，所以连续 [playbackDriftStrikes] 次超过才开始校正。
/// 校正一直持续到漂移小于 [playbackDriftExitMs]，
/// 避免播放停在刚好不超过阈值的位置。
/// 两次校正至少间隔 [playbackMinCorrectionIntervalMs]。
final class DriftCorrection {
  const DriftCorrection()
    : _strikes = 0,
      _correcting = false,
      _lastCorrectionAtMs = null;

  const DriftCorrection._(
    this._strikes,
    this._correcting,
    this._lastCorrectionAtMs,
  );

  final int _strikes;
  final bool _correcting;
  final int? _lastCorrectionAtMs;

  /// [nowMs] 是服务端时间。
  ({DriftCorrection next, int? seekToMs}) check({
    required int positionMs,
    required int expectedMs,
    required int nowMs,
  }) {
    final drift = (positionMs - expectedMs).abs();
    final inSync = _correcting
        ? drift < playbackDriftExitMs
        : drift <= playbackDriftEnterMs;
    if (inSync) {
      return (
        next: DriftCorrection._(0, false, _lastCorrectionAtMs),
        seekToMs: null,
      );
    }
    final strikes = _strikes + 1;
    if (!_correcting && strikes < playbackDriftStrikes) {
      return (
        next: DriftCorrection._(strikes, false, _lastCorrectionAtMs),
        seekToMs: null,
      );
    }
    final last = _lastCorrectionAtMs;
    if (last != null && nowMs - last < playbackMinCorrectionIntervalMs) {
      return (next: DriftCorrection._(strikes, true, last), seekToMs: null);
    }
    return (
      next: DriftCorrection._(strikes, true, nowMs),
      seekToMs: expectedMs,
    );
  }
}
