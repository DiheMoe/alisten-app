import 'dart:math' as math;

import 'package:alisten/domain/playback/lrc.dart';

const _lineReleaseLeadMs = 500;
const _emphasisMinimumMs = 600;
const _emphasisFullMs = 2000;
const _emphasisFloor = 0.35;

/// 唱得久的短词才强调：短音节一闪而过看不出来，长词放大会挤到相邻的字。刚过门槛
/// 的字也要看得出来，所以强度不从零起。
double wordEmphasis(LyricWord word) {
  final length = word.text.trim().length;
  if (word.durationMs <= _emphasisMinimumMs || length == 0 || length >= 8) {
    return 0;
  }
  final held = math.min(word.durationMs, _emphasisFullMs) - _emphasisMinimumMs;
  final range = _emphasisFullMs - _emphasisMinimumMs;
  return _emphasisFloor + (1 - _emphasisFloor) * held / range;
}

final class LineChangeSpring {
  const LineChangeSpring({
    required this.dampingRatio,
    required this.responseSeconds,
  });

  final double dampingRatio;
  final double responseSeconds;

  /// 振幅衰减到千分之一的时间。
  int get settleMs {
    final decayPerSecond = dampingRatio * 2 * math.pi / responseSeconds;
    return (1000 * math.log(1000) / decayPerSecond).round();
  }
}

const _lineSyncedSpring = LineChangeSpring(
  dampingRatio: 0.9,
  responseSeconds: 0.628,
);

final class LyricBreak {
  const LyricBreak({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;
}

/// 整首歌词的时序。提前算好每行的提前量，逐帧调用 [focusAt] 不分配内存。
final class LyricTimeline {
  LyricTimeline(this.lines)
    : wordSynced = lines.any((line) => line.words != null) {
    _springs = [
      for (var index = 0; index < lines.length; index++) _springInto(index),
    ];
    _settleMs = [for (final spring in _springs) spring.settleMs];
    _breaks = [
      for (var index = 0; index < lines.length; index++) _breakAt(index),
    ];
  }

  final List<LyricLine> lines;
  final bool wordSynced;
  late final List<LineChangeSpring> _springs;
  late final List<int> _settleMs;
  late final List<LyricBreak?> _breaks;

  LineChangeSpring springInto(int index) => _springs[index];

  LyricBreak? breakAt(int index) => _breaks[index];

  LineChangeSpring _springInto(int index) {
    if (!wordSynced) return _lineSyncedSpring;
    final previousEnd = index > 0 ? lines[index - 1].endMs : null;
    final gapMs = previousEnd == null ? 0 : lines[index].timeMs - previousEnd;
    final tension = ((gapMs - 200) / 550).clamp(0.0, 1.0);
    return LineChangeSpring(
      dampingRatio: 0.9 - 0.12 * tension,
      responseSeconds: 0.48 + 0.27 * tension,
    );
  }

  LyricBreak? _breakAt(int index) {
    if (!lines[index].isBlank) return null;
    final startMs = lines[index].timeMs;
    for (var next = index + 1; next < lines.length; next++) {
      if (lines[next].isBlank) continue;
      final endMs = lines[next].timeMs;
      if (endMs - startMs < lyricBreakMinimumMs) return null;
      return LyricBreak(startMs: startMs, endMs: endMs);
    }
    return null;
  }

  /// 逐字行唱完之前不让位。
  int releaseMs(int index) {
    final line = lines[index];
    if (line.words case final words?) return words.last.endMs;
    if (index + 1 < lines.length) {
      return lines[index + 1].timeMs - _lineReleaseLeadMs;
    }
    return line.endMs ?? line.timeMs;
  }

  /// 换行要在下一行开唱时到位，所以比行的时间更早。只取决于位置，暂停、恢复和
  /// 跳转后结果都一致。
  int focusAt(int positionMs) {
    final current = lineIndexAt(lines, positionMs);
    final next = current + 1;
    if (next >= lines.length) return current;
    if (positionMs < lines[next].timeMs - _settleMs[next]) return current;
    if (current >= 0 && positionMs <= releaseMs(current)) return current;
    return next;
  }

  int? nextFocusChangeMs(int positionMs) {
    final focus = focusAt(positionMs);
    final next = focus + 1;
    if (next >= lines.length) return null;
    final startMs = lines[next].timeMs;
    var change = startMs - _settleMs[next];
    if (focus >= 0) {
      change = math.max(change, releaseMs(focus) + 1);
      // 提前到来的行要等到开始时间才算当前行，之前下一行不会接替它。
      change = math.max(change, lines[focus].timeMs);
    }
    return math.min(change, startMs);
  }
}
