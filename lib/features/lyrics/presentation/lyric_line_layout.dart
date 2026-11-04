import 'dart:math' as math;

import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/domain/playback/lyric_timing.dart';
import 'package:flutter/widgets.dart';

const _translationGapEm = 0.15;
const _glowRadiusEm = 0.12;

@immutable
final class LyricTextStyles {
  const LyricTextStyles({
    required this.main,
    required this.translation,
    required this.scaler,
  });

  final TextStyle main;
  final TextStyle translation;
  final TextScaler scaler;

  double get em => scaler.scale(main.fontSize!);

  @override
  bool operator ==(Object other) {
    return other is LyricTextStyles &&
        other.main == main &&
        other.translation == translation &&
        other.scaler == scaler;
  }

  @override
  int get hashCode => Object.hash(main, translation, scaler);
}

final class LyricSweepStep {
  const LyricSweepStep({
    required this.startMs,
    required this.endMs,
    required this.startX,
    required this.endX,
  });

  final int startMs;
  final int endMs;
  final double startX;
  final double endX;
}

final class LyricFragment {
  const LyricFragment({
    required this.text,
    required this.painter,
    required this.glow,
    required this.offset,
    required this.word,
    required this.emphasis,
    required this.index,
    required this.count,
    required this.wordCenterX,
  });

  final String text;
  final TextPainter painter;
  final TextPainter? glow;
  final Offset offset;
  final LyricWord word;
  final double emphasis;

  /// 强调字里的字符序号和字符总数，从 1 计。
  final int index;
  final int count;
  final double wordCenterX;

  double get centerX => offset.dx + painter.width / 2;
}

final class LyricRow {
  LyricRow({
    required this.rect,
    required this.baseline,
    required this.fragments,
    required this.steps,
  });

  final Rect rect;
  final double baseline;
  final List<LyricFragment> fragments;
  final List<LyricSweepStep> steps;

  double edgeAt(int positionMs) {
    var edge = rect.left;
    for (final step in steps) {
      if (positionMs <= step.startMs) continue;
      final length = math.max(step.endMs - step.startMs, 1);
      final progress = ((positionMs - step.startMs) / length).clamp(0.0, 1.0);
      final x = step.startX + (step.endX - step.startX) * progress;
      edge = math.max(edge, x);
    }
    return edge;
  }

  double steppedEdgeAt(int positionMs) {
    var edge = rect.left;
    for (final step in steps) {
      if (positionMs > step.startMs) edge = math.max(edge, step.endX);
    }
    return edge;
  }
}

final class LyricLineLayout {
  LyricLineLayout(this.line, this.styles, this.width)
    : main = _paragraph(line.text, styles.main, styles.scaler, width),
      translation = switch (line.translation) {
        final text? => _paragraph(
          text,
          styles.translation,
          styles.scaler,
          width,
        ),
        null => null,
      };

  final LyricLine line;
  final LyricTextStyles styles;
  final double width;
  final TextPainter main;
  final TextPainter? translation;

  List<LyricRow>? _rows;

  double get _translationGap => _translationGapEm * styles.em;

  double get height {
    if (line.isBlank) return 0;
    final translation = this.translation;
    if (translation == null) return main.height;
    return main.height + _translationGap + translation.height;
  }

  Offset get translationOffset => Offset(0, main.height + _translationGap);

  /// 片段要用才建：只有当前行和下一行需要。
  List<LyricRow> get rows => _rows ??= _buildRows();

  bool get hasRows => _rows != null;

  void releaseRows() {
    for (final row in _rows ?? const <LyricRow>[]) {
      for (final fragment in row.fragments) {
        fragment.painter.dispose();
        fragment.glow?.dispose();
      }
    }
    _rows = null;
  }

  List<LyricRow> _buildRows() {
    final words = line.words;
    if (words == null) return const [];
    final spans = <_WordSpan>[];
    var cursor = 0;
    for (final word in words) {
      spans.add(_WordSpan(word, cursor, cursor + word.text.length));
      cursor += word.text.length;
    }
    final metrics = main.computeLineMetrics();
    final rows = <_RowDraft>[];
    var start = 0;
    for (final metric in metrics) {
      final range = main.getLineBoundary(TextPosition(offset: start));
      rows.add(_RowDraft(metric, range.start, range.end));
      if (range.end <= start) break;
      start = range.end;
    }
    for (final span in spans) {
      for (final row in rows) {
        final from = math.max(span.start, row.start);
        final to = math.min(span.end, row.end);
        if (from >= to) continue;
        final slice = _Slice(span, row, from, to, _extent(from, to));
        span.slices.add(slice);
        row.slices.add(slice);
      }
      _shareTime(span);
    }
    return [for (final row in rows) _finishRow(row)];
  }

  (double, double)? _extent(int from, int to) {
    final boxes = main.getBoxesForSelection(
      TextSelection(baseOffset: from, extentOffset: to),
    );
    if (boxes.isEmpty) return null;
    return (
      boxes.map((box) => box.left).reduce(math.min),
      boxes.map((box) => box.right).reduce(math.max),
    );
  }

  // 折行时一个字有多段，时间按宽度分给各段，点亮的速度才均匀。
  void _shareTime(_WordSpan span) {
    final word = span.word;
    final total = span.slices.fold<double>(0, (sum, s) => sum + s.width);
    var elapsed = 0.0;
    for (final (index, slice) in span.slices.indexed) {
      final share = total > 0 ? slice.width / total : 1 / span.slices.length;
      slice.startMs = word.startMs + (elapsed * word.durationMs).round();
      elapsed += share;
      slice.endMs = index == span.slices.length - 1
          ? word.endMs
          : word.startMs + (elapsed * word.durationMs).round();
    }
  }

  LyricRow _finishRow(_RowDraft draft) {
    final metric = draft.metric;
    final top = metric.baseline - metric.ascent;
    var left = metric.left;
    var right = metric.left + metric.width;
    final fragments = <LyricFragment>[];
    final steps = <LyricSweepStep>[];
    for (final slice in draft.slices) {
      final extent = slice.extent;
      if (extent == null) continue;
      left = math.min(left, extent.$1);
      right = math.max(right, extent.$2);
      steps.add(
        LyricSweepStep(
          startMs: slice.startMs,
          endMs: slice.endMs,
          startX: extent.$1,
          endX: extent.$2,
        ),
      );
      final word = slice.span.word;
      final emphasis = wordEmphasis(word);
      if (emphasis > 0) {
        _addCharacters(fragments, slice, metric, emphasis);
      } else if (line.text.substring(slice.from, slice.to).trim().isNotEmpty) {
        fragments.add(
          _fragment(
            from: slice.from,
            to: slice.to,
            x: extent.$1,
            metric: metric,
            word: word,
            emphasis: 0,
            index: 1,
            count: 1,
            wordCenterX: (extent.$1 + extent.$2) / 2,
          ),
        );
      }
    }
    return LyricRow(
      rect: Rect.fromLTRB(left, top, right, top + metric.height),
      baseline: metric.baseline,
      fragments: fragments,
      steps: steps,
    );
  }

  void _addCharacters(
    List<LyricFragment> fragments,
    _Slice slice,
    LineMetrics metric,
    double emphasis,
  ) {
    final span = slice.span;
    final count = span.word.text.trim().characters.length;
    var offset = span.start;
    var index = 0;
    final wordEnds = [for (final part in span.slices) ?part.extent];
    final wordCenterX =
        (wordEnds.map((e) => e.$1).reduce(math.min) +
            wordEnds.map((e) => e.$2).reduce(math.max)) /
        2;
    for (final character in span.word.text.characters) {
      final from = offset;
      final to = offset += character.length;
      if (character.trim().isEmpty) continue;
      index++;
      if (from < slice.from || to > slice.to) continue;
      final extent = _extent(from, to);
      if (extent == null) continue;
      fragments.add(
        _fragment(
          from: from,
          to: to,
          x: extent.$1,
          metric: metric,
          word: span.word,
          emphasis: emphasis,
          index: index,
          count: count,
          wordCenterX: wordCenterX,
        ),
      );
    }
  }

  LyricFragment _fragment({
    required int from,
    required int to,
    required double x,
    required LineMetrics metric,
    required LyricWord word,
    required double emphasis,
    required int index,
    required int count,
    required double wordCenterX,
  }) {
    final text = line.text.substring(from, to);
    final painter = _paragraph(text, styles.main, styles.scaler, null);
    // 中文回退字体与拉丁字体的上伸不同，要按基线而不是行顶对齐。
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    return LyricFragment(
      text: text,
      painter: painter,
      glow: emphasis > 0
          ? _paragraph(
              text,
              styles.main.copyWith(
                shadows: [
                  Shadow(
                    color: styles.main.color!,
                    blurRadius: _glowRadiusEm * styles.em,
                  ),
                ],
              ),
              styles.scaler,
              null,
            )
          : null,
      offset: Offset(x, metric.baseline - baseline),
      word: word,
      emphasis: emphasis,
      index: index,
      count: count,
      wordCenterX: wordCenterX,
    );
  }

  void dispose() {
    main.dispose();
    translation?.dispose();
    releaseRows();
  }
}

TextPainter _paragraph(
  String text,
  TextStyle style,
  TextScaler scaler,
  double? width,
) {
  return TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout(maxWidth: width ?? double.infinity);
}

final class _WordSpan {
  _WordSpan(this.word, this.start, this.end);

  final LyricWord word;
  final int start;
  final int end;
  final List<_Slice> slices = [];
}

final class _RowDraft {
  _RowDraft(this.metric, this.start, this.end);

  final LineMetrics metric;
  final int start;
  final int end;
  final List<_Slice> slices = [];
}

final class _Slice {
  _Slice(this.span, this.row, this.from, this.to, this.extent);

  final _WordSpan span;
  final _RowDraft row;
  final int from;
  final int to;
  final (double, double)? extent;
  int startMs = 0;
  int endMs = 0;

  double get width => switch (extent) {
    (final left, final right) => right - left,
    null => 0,
  };
}
