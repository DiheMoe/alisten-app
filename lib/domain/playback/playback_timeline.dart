const playbackDriftCheckIntervalMs = 2000;
const playbackDriftThresholdMs = 1000;
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

/// 单次超过 [playbackDriftThresholdMs] 可能只是会自行恢复的卡顿，
/// 而每次 seek 都听得出来，所以连续 [playbackDriftStrikes] 次超过才校正。
/// 校正后回到阈值以内即算同步：seek 之后要过一阵才出声，有的设备上超过半秒，
/// 要求更小的漂移会每次检查都 seek。
/// 两次校正至少间隔 [playbackMinCorrectionIntervalMs]。
final class DriftCorrection {
  const DriftCorrection() : _strikes = 0, _lastCorrectionAtMs = null;

  const DriftCorrection._(this._strikes, this._lastCorrectionAtMs);

  final int _strikes;
  final int? _lastCorrectionAtMs;

  /// [nowMs] 是服务端时间。
  ({DriftCorrection next, int? seekToMs}) check({
    required int positionMs,
    required int expectedMs,
    required int nowMs,
  }) {
    final last = _lastCorrectionAtMs;
    if ((positionMs - expectedMs).abs() <= playbackDriftThresholdMs) {
      return (next: DriftCorrection._(0, last), seekToMs: null);
    }
    final strikes = _strikes + 1;
    if (strikes < playbackDriftStrikes ||
        (last != null && nowMs - last < playbackMinCorrectionIntervalMs)) {
      return (next: DriftCorrection._(strikes, last), seekToMs: null);
    }
    return (next: DriftCorrection._(strikes, nowMs), seekToMs: expectedMs);
  }
}
