import 'dart:math' as math;

import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/domain/playback/lyric_timing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';

const _staggerSeconds = 0.05;
const _liftEm = 0.12;
const _emphasisScale = 0.14;
const _emphasisGlow = 0.4;

const _dotsLightDelay = 1.0;
const _dotsFadeOutLead = 1.8;
const _dotsUnlit = 0.1;
const _dotsAppear = 0.8;
const _dotsInhale = 1.2;
const _dotsExhale = 0.9;
const _dotsBreathDelay = 0.2;
const _dotsSwell = 1.0;
const _dotsVanishDelay = 1.0;
const _dotsVanishFade = 0.3;
const _dotsVanishShrink = 0.5;
const _dotsVanishScale = 0.2;

/// 歌曲位置和单调时间。只有当前行和过渡中的行订阅，其他行不重绘。
final class LyricFrameClock extends ChangeNotifier {
  int _positionMs = 0;
  double _nowSeconds = 0;
  double _heldUntil = 0;

  int get positionMs => _positionMs;
  double get nowSeconds => _nowSeconds;

  /// 过渡中的行声明需要连续帧到哪一刻。
  bool get busy => _nowSeconds < _heldUntil;

  void holdUntil(double seconds) {
    _heldUntil = math.max(_heldUntil, seconds);
  }

  void tick({required int positionMs, required double nowSeconds}) {
    _positionMs = positionMs;
    _nowSeconds = nowSeconds;
    notifyListeners();
  }
}

const _settled = Tolerance(distance: 0.1, velocity: 1);

/// 内容瞬间到位，每行绘制时再用弹簧从旧位置追上来，所以滚动位置不用逐帧改，
/// 拖动手势也不受影响。
final class LyricMotion extends ChangeNotifier {
  List<double> _lag = const [];
  List<SpringSimulation?> _springs = const [];
  List<double> _startedAt = const [];
  List<double> _delays = const [];
  List<double> _speeds = const [];
  int? _gapRow;
  double _gapExtent = 0;
  bool _active = false;

  bool get active => _active;

  void configure(int rowCount) {
    _lag = List.filled(rowCount, 0);
    _springs = List.filled(rowCount, null);
    _startedAt = List.filled(rowCount, 0);
    _delays = List.filled(rowCount, 0);
    _speeds = List.filled(rowCount, 1);
    _gapRow = null;
    _gapExtent = 0;
    _active = false;
  }

  void clear() => configure(_lag.length);

  double extraOf(int row) {
    final gap = _gapRow;
    return gap != null && row > gap ? _gapExtent : 0;
  }

  double offsetOf(int row) => extraOf(row) + _lag[row];

  /// 展开只发生在绘制阶段：布局不变，换行时也就不会有一帧错位。
  void openGap(int? row, double extent) {
    _gapRow = row;
    _gapExtent = extent;
  }

  void shift({
    required double Function(int row) delta,
    required LineChangeSpring spring,
    required double nowSeconds,
    double Function(int row)? delay,
    double speed = 1,
  }) {
    final omega = 2 * math.pi / spring.responseSeconds;
    final description = SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: omega * omega,
      ratio: spring.dampingRatio,
    );
    advance(nowSeconds);
    for (var row = 0; row < _lag.length; row++) {
      final moved = delta(row);
      final running = _springs[row];
      if (moved == 0 && running == null) continue;
      final elapsed = _elapsed(row, nowSeconds);
      final velocity = running == null
          ? 0.0
          : running.dx(elapsed) * _speeds[row] / speed;
      final from = _lag[row] + moved;
      _lag[row] = from;
      _springs[row] = SpringSimulation(
        description,
        from,
        0,
        velocity,
        tolerance: _settled,
      );
      _startedAt[row] = nowSeconds;
      _delays[row] = delay?.call(row) ?? 0;
      _speeds[row] = speed;
      _active = true;
    }
    notifyListeners();
  }

  double _elapsed(int row, double nowSeconds) {
    final since = nowSeconds - _startedAt[row] - _delays[row];
    return math.max(since, 0) * _speeds[row];
  }

  void advance(double nowSeconds) {
    if (!_active) return;
    var active = false;
    for (var row = 0; row < _lag.length; row++) {
      final spring = _springs[row];
      if (spring == null) continue;
      final elapsed = _elapsed(row, nowSeconds);
      if (spring.isDone(elapsed)) {
        _lag[row] = 0;
        _springs[row] = null;
      } else {
        _lag[row] = spring.x(elapsed);
        active = true;
      }
    }
    _active = active;
    notifyListeners();
  }
}

double staggerDelay({
  required int row,
  required int first,
  required int last,
  required bool forward,
}) {
  final step = _staggerSeconds * (forward ? 1 : 0.5);
  final index = row.clamp(first, last) - first;
  final distance = forward ? index : last - first - index;
  return step * math.max(distance - 1, 0);
}

final _lift = SpringSimulation(
  const SpringDescription(mass: 1, stiffness: 144, damping: 22),
  0,
  1,
  0,
);

double liftAt(int elapsedMs) {
  return elapsedMs <= 0 ? 0 : _lift.x(elapsedMs / 1000);
}

// 临界阻尼是线性的，升起和回落可以直接叠加，字的状态因此是位置的纯函数：暂停时
// 自动不动，跳转后立即正确。
double _criticalStep(double seconds, double omega) {
  if (seconds <= 0) return 0;
  return 1 - (1 + omega * seconds) * math.exp(-omega * seconds);
}

@immutable
final class GlyphMotion {
  const GlyphMotion({
    required this.scale,
    required this.liftEm,
    required this.shiftX,
    required this.glow,
  });

  final double scale;
  final double liftEm;
  final double shiftX;
  final double glow;
}

GlyphMotion glyphMotionAt({
  required int positionMs,
  required LyricWord word,
  required double emphasis,
  required int index,
  required int count,
  required double lineHeightEm,
  required double offsetFromWordCenter,
  int? releasedAtMs,
}) {
  final elapsedMs = positionMs - word.startMs;
  if (emphasis <= 0) {
    return GlyphMotion(
      scale: 1,
      liftEm: _liftEm * liftAt(elapsedMs),
      shiftX: 0,
      glow: 0,
    );
  }
  final elapsed = elapsedMs / 1000;
  final duration = math.max(word.durationMs / 1000, 0.001);
  final stagger = math.min(0.4 * duration / count, 0.4);
  final up = index * stagger;
  var down = 2 * duration / count + index * stagger;
  if (releasedAtMs != null) {
    down = math.min(down, (releasedAtMs - word.startMs) / 1000);
  }
  final omega = 2 * math.pi / math.min(duration, 3);
  final rise = _criticalStep(elapsed - up, omega);
  final growth =
      _emphasisScale * emphasis * (rise - _criticalStep(elapsed - down, omega));
  return GlyphMotion(
    scale: 1 + growth,
    liftEm: _liftEm * rise + growth * lineHeightEm / 4,
    shiftX: growth * offsetFromWordCenter / 2,
    glow:
        _emphasisGlow *
        emphasis *
        _criticalStep(elapsed, omega) *
        (1 - liftAt(positionMs - word.endMs).clamp(0.0, 1.0)),
  );
}

@immutable
final class BreakDots {
  const BreakDots({
    required this.scale,
    required this.opacity,
    required this.lit,
  });

  final double scale;
  final double opacity;

  /// 三个点各自的亮度。
  final List<double> lit;
}

double _progress(double value, double start, double length) {
  return ((value - start) / length).clamp(0.0, 1.0);
}

double _lerp(double from, double to, double t) => from + (to - from) * t;

double _easeOut(double t) => 1 - (1 - t) * (1 - t);

BreakDots breakDotsAt(LyricBreak gap, int positionMs, {required bool smooth}) {
  final start = gap.startMs / 1000;
  final end = gap.endMs / 1000;
  final t = positionMs / 1000;
  final fadeOutAt = end - _dotsFadeOutLead;
  final lightFrom = start + _dotsLightDelay;
  final lightEach = math.max((fadeOutAt - lightFrom) / 3, 0.1);
  double litAt(int dot) {
    final from = lightFrom + dot * lightEach;
    if (!smooth) return t >= from + lightEach ? 1 : _dotsUnlit;
    return _lerp(_dotsUnlit, 1, _progress(t, from, lightEach));
  }

  final lit = List<double>.unmodifiable([
    for (var dot = 0; dot < 3; dot++) litAt(dot),
  ]);
  if (!smooth) return BreakDots(scale: 1, opacity: 1, lit: lit);
  final span = math.max(fadeOutAt - start, 0.1);
  final breath = span / math.max((span * 0.25).floor(), 1) * 0.5;
  final breathing = math.min(t, fadeOutAt) - start;
  final turn = (math.max(breathing, 0) / breath).floor();
  double target(int number) {
    if (number == 0) return 1;
    return number.isOdd ? _dotsInhale : _dotsExhale;
  }

  var scale = _lerp(
    target(turn),
    target(turn + 1),
    _easeOut(
      _progress(
        breathing,
        turn * breath + _dotsBreathDelay,
        math.max(breath - 2 * _dotsBreathDelay, 0.05),
      ),
    ),
  );
  var opacity = _progress(t, start, _dotsAppear);
  if (t > fadeOutAt) {
    scale = _lerp(
      scale,
      _dotsInhale,
      _easeOut(_progress(t, fadeOutAt, _dotsSwell)),
    );
    final vanishAt = fadeOutAt + _dotsVanishDelay;
    scale = _lerp(
      scale,
      _dotsVanishScale,
      _progress(t, vanishAt, _dotsVanishShrink),
    );
    opacity *= 1 - _progress(t, vanishAt, _dotsVanishFade);
  }
  return BreakDots(scale: scale, opacity: opacity, lit: lit);
}
