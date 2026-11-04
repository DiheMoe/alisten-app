import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/domain/playback/lyric_timing.dart';
import 'package:alisten/features/lyrics/presentation/lyric_line_layout.dart';
import 'package:alisten/features/lyrics/presentation/lyric_motion.dart';
import 'package:alisten/features/lyrics/presentation/lyric_snapshots.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

enum LyricLinePhase { upcoming, focused, past }

const _idleAlpha = 0.3;
const _scrollingIdleAlpha = 0.55;
const _unsungAlpha = 0.25;
const _translationAlpha = 0.5;
const _idleScale = 0.98;
const _featherEm = 0.6;

// 手机上字小，笔画只有两三 dp，半径大了就读不出来。
const _baseBlurEm = 0.03;
const _blurStepEm = 0.01;
const _maxBlurEm = 0.05;

/// 歌词是模糊的，半分辨率看不出差别，内存只要四分之一。
const _snapshotScale = 0.5;

// 多要几帧：时间恰好落在终点前一点时，过渡收不了尾。
const _holdMarginSeconds = 0.05;

const _dotEm = 0.25;
const _dotGapEm = 0.17;
const lyricBreakHeightEm = 0.83;

// 放大、上浮和发光都会超出行的范围。
const _rowOverflowXEm = 0.3;
const _rowOverflowYEm = 0.35;

double lyricBlurEm({
  required LyricLinePhase phase,
  required int distance,
  required bool scrolling,
}) {
  if (scrolling || phase == LyricLinePhase.focused) return 0;
  if (phase == LyricLinePhase.past) return _baseBlurEm;
  final blur = _baseBlurEm + (distance - 2) * _blurStepEm;
  return blur.clamp(0.0, _maxBlurEm);
}

double lyricIdleAlpha({required bool scrolling}) {
  return scrolling ? _scrollingIdleAlpha : _idleAlpha;
}

int lyricBlurLevel(double blurEm) => (blurEm / _blurStepEm).round();

class LyricLineRow extends LeafRenderObjectWidget {
  const LyricLineRow({
    required this.index,
    required this.line,
    required this.gap,
    required this.styles,
    required this.phase,
    required this.distance,
    required this.scrolling,
    required this.smooth,
    required this.clock,
    required this.snapshots,
    this.prepared = false,
    super.key,
  });

  final int index;
  final LyricLine line;
  final LyricBreak? gap;
  final LyricTextStyles styles;
  final LyricLinePhase phase;
  final int distance;
  final bool scrolling;
  final bool smooth;
  final LyricFrameClock clock;
  final LyricSnapshotCache snapshots;

  /// 下一行提前建片段：轮到它时正是最忙的一帧。
  final bool prepared;

  @override
  RenderLyricLine createRenderObject(BuildContext context) {
    return RenderLyricLine(
      index: index,
      line: line,
      gap: gap,
      styles: styles,
      phase: phase,
      distance: distance,
      scrolling: scrolling,
      smooth: smooth,
      clock: clock,
      snapshots: snapshots,
      prepared: prepared,
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderLyricLine renderObject) {
    renderObject
      ..pixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..update(
        index: index,
        line: line,
        gap: gap,
        styles: styles,
        phase: phase,
        distance: distance,
        scrolling: scrolling,
        smooth: smooth,
        clock: clock,
        snapshots: snapshots,
        prepared: prepared,
      );
  }
}

class RenderLyricLine extends RenderBox {
  RenderLyricLine({
    required this._index,
    required this._line,
    required this._gap,
    required this._styles,
    required LyricLinePhase phase,
    required int distance,
    required bool scrolling,
    required this._smooth,
    required this._clock,
    required this._snapshots,
    required this._prepared,
    required this.pixelRatio,
  }) : _phase = phase,
       _distance = distance,
       _scrolling = scrolling,
       _selection = phase == LyricLinePhase.focused ? 1 : 0,
       _selectionFrom = phase == LyricLinePhase.focused ? 1 : 0,
       _blur = lyricBlurEm(
         phase: phase,
         distance: distance,
         scrolling: scrolling,
       ),
       _idle = lyricIdleAlpha(scrolling: scrolling);

  int _index;
  LyricLine _line;
  LyricBreak? _gap;
  LyricTextStyles _styles;
  LyricLinePhase _phase;
  int _distance;
  bool _scrolling;
  bool _smooth;
  LyricFrameClock _clock;
  LyricSnapshotCache _snapshots;
  bool _prepared;
  double pixelRatio;

  LyricLineLayout? _layout;

  // 选中程度和它的过渡。
  double _selection;
  double _selectionFrom;
  double? _selectionStart;

  double _idle;
  double _idleFrom = _idleAlpha;
  double? _idleStart;

  // 模糊半径和它的交叉淡化。
  double _blur;
  double _blurFrom = 0;
  double? _blurStart;

  bool _listening = false;
  bool _rowsQueued = false;

  /// 离开当前行的时刻（歌曲位置），强调字从这里开始回落。
  int? _releasedAtMs;

  @visibleForTesting
  int debugPaintCount = 0;

  @visibleForTesting
  double get debugSelection => _selection;

  @visibleForTesting
  bool debugUsesSnapshot = false;

  @visibleForTesting
  bool get debugHasFragments => _layout?.hasRows ?? false;

  bool get _focused => _phase == LyricLinePhase.focused;
  bool get _transitioning =>
      _selectionStart != null || _blurStart != null || _idleStart != null;

  void update({
    required int index,
    required LyricLine line,
    required LyricBreak? gap,
    required LyricTextStyles styles,
    required LyricLinePhase phase,
    required int distance,
    required bool scrolling,
    required bool smooth,
    required LyricFrameClock clock,
    required LyricSnapshotCache snapshots,
    required bool prepared,
  }) {
    final relayout =
        !identical(line, _line) ||
        styles != _styles ||
        !identical(snapshots, _snapshots);
    var repaint =
        relayout ||
        index != _index ||
        !identical(gap, _gap) ||
        phase != _phase ||
        scrolling != _scrolling ||
        smooth != _smooth;
    final clockChanged = !identical(clock, _clock);
    if (clockChanged && _listening) {
      _clock.removeListener(_onTick);
      _listening = false;
    }
    final wasFocused = _focused;
    _index = index;
    _line = line;
    _gap = gap;
    _styles = styles;
    _smooth = smooth;
    _clock = clock;
    _snapshots = snapshots;
    _prepared = prepared;
    final phaseChanged = phase != _phase;
    _phase = phase;
    _distance = distance;
    final scrollingChanged = scrolling != _scrolling;
    _scrolling = scrolling;
    if (relayout) {
      _layout?.dispose();
      _layout = null;
      markNeedsLayout();
    }
    if (phaseChanged) {
      if (wasFocused) _releasedAtMs = _clock.positionMs;
      if (phase == LyricLinePhase.focused) _releasedAtMs = null;
      _startSelection();
    }
    if (scrollingChanged) _startIdle();
    final level = lyricBlurLevel(_blur);
    _startBlur();
    repaint = repaint || lyricBlurLevel(_blur) != level;
    _syncListening();
    _syncRows();
    if (repaint) markNeedsPaint();
  }

  double get _now => _clock.nowSeconds;

  double get _stateSeconds =>
      AlistenDurations.lyricState.inMicroseconds /
      Duration.microsecondsPerSecond;

  double get _blurSeconds =>
      AlistenDurations.lyricBlur.inMicroseconds /
      Duration.microsecondsPerSecond;

  void _startSelection() {
    final target = _focused ? 1.0 : 0.0;
    if (!_smooth || !attached) {
      _selection = target;
      _selectionStart = null;
      return;
    }
    _selectionFrom = _selection;
    _selectionStart = _now;
    _clock.holdUntil(_now + _stateSeconds + _holdMarginSeconds);
  }

  void _startIdle() {
    final target = lyricIdleAlpha(scrolling: _scrolling);
    if (!_smooth || !attached) {
      _idle = target;
      _idleStart = null;
      return;
    }
    _idleFrom = _idle;
    _idleStart = _now;
    _clock.holdUntil(_now + _stateSeconds + _holdMarginSeconds);
  }

  double get _targetBlur =>
      lyricBlurEm(phase: _phase, distance: _distance, scrolling: _scrolling);

  // 离开当前行时先清晰地淡出再模糊：快照里原文和翻译是同一个透明度，提前换上
  // 翻译会突然变亮，上浮的字也会一下落回去。
  void _startBlur() {
    if (_selectionStart != null && !_focused) return;
    final target = _targetBlur;
    if (lyricBlurLevel(target) == lyricBlurLevel(_blur)) return;
    if (!_smooth || !attached) {
      _blur = target;
      _blurStart = null;
      return;
    }
    _blurFrom = _blur;
    _blur = target;
    _blurStart = _now;
    _clock.holdUntil(_now + _blurSeconds + _holdMarginSeconds);
  }

  void _advance() {
    final selecting = _selectionStart;
    final target = _focused ? 1.0 : 0.0;
    if (selecting != null) {
      final t = ((_now - selecting) / _stateSeconds).clamp(0.0, 1.0);
      _selection = ui.lerpDouble(
        _selectionFrom,
        target,
        Curves.easeInOut.transform(t),
      )!;
      if (t >= 1) {
        _selectionStart = null;
        _startBlur();
        _syncRows();
      }
    }
    final idling = _idleStart;
    if (idling != null) {
      final t = ((_now - idling) / _stateSeconds).clamp(0.0, 1.0);
      _idle = ui.lerpDouble(
        _idleFrom,
        lyricIdleAlpha(scrolling: _scrolling),
        Curves.easeInOut.transform(t),
      )!;
      if (t >= 1) _idleStart = null;
    }
    final blurring = _blurStart;
    if (blurring != null && _now - blurring >= _blurSeconds) _blurStart = null;
  }

  double get _blurMix {
    final start = _blurStart;
    if (start == null) return 1;
    return ((_now - start) / _blurSeconds).clamp(0.0, 1.0);
  }

  bool get _wantsRows {
    return _line.words != null &&
        (_focused || _prepared || _selectionStart != null);
  }

  void _syncRows() {
    if (!_wantsRows) {
      _layout?.releaseRows();
      return;
    }
    if (_rowsQueued) return;
    _rowsQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _rowsQueued = false;
      if (attached && _wantsRows) _layout?.rows;
    });
  }

  bool get _needsClock => _focused || _transitioning;

  void _syncListening() {
    if (!attached) return;
    if (_needsClock == _listening) return;
    _listening = _needsClock;
    if (_listening) {
      _clock.addListener(_onTick);
    } else {
      _clock.removeListener(_onTick);
    }
  }

  void _onTick() {
    _advance();
    _syncListening();
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _syncListening();
  }

  @override
  void detach() {
    if (_listening) {
      _clock.removeListener(_onTick);
      _listening = false;
    }
    super.detach();
  }

  @override
  void dispose() {
    _layout?.dispose();
    super.dispose();
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    var layout = _layout;
    if (layout == null || layout.width != width) {
      layout?.dispose();
      layout = _layout = LyricLineLayout(_line, _styles, width);
    }
    size = constraints.constrain(Size(width, layout.height));
    _syncRows();
  }

  double _heightFor(double width) {
    final layout = LyricLineLayout(_line, _styles, width);
    final height = layout.height;
    layout.dispose();
    return height;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    return constraints.constrain(Size(width, _heightFor(width)));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    debugPaintCount++;
    _advance();
    final canvas = context.canvas;
    final layout = _layout!;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    if (_line.isBlank) {
      _paintBreak(canvas);
    } else {
      final scale = ui.lerpDouble(_idleScale, 1, _selection)!;
      final middle = size.height / 2;
      canvas
        ..translate(0, middle)
        ..scale(scale)
        ..translate(0, -middle);
      _paintLine(canvas, layout);
    }
    canvas.restore();
  }

  void _paintLine(Canvas canvas, LyricLineLayout layout) {
    final level = lyricBlurLevel(_blur);
    final overall = ui.lerpDouble(_idle, 1, _selection)!;
    void paintAt(int level, double weight) {
      if (weight <= 0) return;
      if (level == 0 || !_paintSnapshot(canvas, level, overall * weight)) {
        _paintSharp(canvas, layout, weight);
      }
    }

    debugUsesSnapshot = false;
    if (_blurStart == null) {
      paintAt(level, 1);
    } else {
      final mix = _blurMix;
      paintAt(lyricBlurLevel(_blurFrom), 1 - mix);
      paintAt(level, mix);
    }
  }

  void _paintSharp(Canvas canvas, LyricLineLayout layout, double opacity) {
    final main = layout.main;
    final bounds = Offset.zero & size;
    final rows = _line.words == null || _selection <= 0
        ? const <LyricRow>[]
        : layout.rows;
    if (rows.isEmpty) {
      final alpha = ui.lerpDouble(_idle, 1, _selection)! * opacity;
      _withOpacity(canvas, bounds.inflate(_styles.em), alpha, () {
        main.paint(canvas, Offset.zero);
      });
    } else {
      _paintRows(canvas, rows, opacity);
    }
    final translation = layout.translation;
    if (translation == null) return;
    final alpha =
        ui.lerpDouble(_idle, _translationAlpha, _selection)! * opacity;
    _withOpacity(canvas, bounds, alpha, () {
      translation.paint(canvas, layout.translationOffset);
    });
  }

  void _withOpacity(
    Canvas canvas,
    Rect bounds,
    double opacity,
    VoidCallback paint,
  ) {
    if (opacity >= 1) {
      paint();
      return;
    }
    if (opacity <= 0) return;
    canvas.saveLayer(
      bounds,
      Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
    );
    paint();
    canvas.restore();
  }

  void _paintRows(Canvas canvas, List<LyricRow> rows, double opacity) {
    final em = _styles.em;
    final position = _clock.positionMs;
    final feather = _smooth ? _featherEm * em : 1.0;
    final sung = ui.lerpDouble(_idle, 1, _selection)! * opacity;
    final unsung = ui.lerpDouble(_idle, _unsungAlpha, _selection)! * opacity;
    final sungColor = Color.fromRGBO(255, 255, 255, sung);
    final unsungColor = Color.fromRGBO(255, 255, 255, unsung);
    for (final row in rows) {
      final rect = row.rect;
      final bounds = Rect.fromLTRB(
        rect.left - _rowOverflowXEm * em,
        rect.top - _rowOverflowYEm * em,
        rect.right + _rowOverflowXEm * em,
        rect.bottom + _rowOverflowYEm * em,
      );
      // 同一个点亮边贯穿全行，发光也在图层内，所以发光随字一起由暗变亮。
      canvas.saveLayer(bounds, Paint());
      for (final fragment in row.fragments) {
        _paintFragment(canvas, fragment, position, em, rect.height / em);
      }
      final walked = _smooth
          ? row.edgeAt(position)
          : row.steppedEdgeAt(position);
      final width = math.max(rect.width, 1.0);
      final edge = rect.left + (walked - rect.left) * (width + feather) / width;
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            Offset(edge - feather, 0),
            Offset(edge, 0),
            [sungColor, unsungColor],
          ),
      );
      canvas.restore();
    }
  }

  void _paintFragment(
    Canvas canvas,
    LyricFragment fragment,
    int position,
    double em,
    double lineHeightEm,
  ) {
    if (!_smooth) {
      fragment.painter.paint(canvas, fragment.offset);
      return;
    }
    final motion = glyphMotionAt(
      positionMs: position,
      word: fragment.word,
      emphasis: fragment.emphasis,
      index: fragment.index,
      count: fragment.count,
      lineHeightEm: lineHeightEm,
      offsetFromWordCenter: fragment.centerX - fragment.wordCenterX,
      releasedAtMs: _releasedAtMs,
    );
    final painter = fragment.painter;
    final center = fragment.offset + Offset(painter.width, painter.height) / 2;
    canvas.save();
    canvas
      ..translate(center.dx + motion.shiftX, center.dy - motion.liftEm * em)
      ..scale(motion.scale)
      ..translate(-painter.width / 2, -painter.height / 2);
    final glow = fragment.glow;
    if (glow != null && motion.glow > 0) {
      _withOpacity(
        canvas,
        (Offset.zero & painter.size).inflate(em),
        motion.glow,
        () => glow.paint(canvas, Offset.zero),
      );
    }
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  bool _paintSnapshot(Canvas canvas, int level, double opacity) {
    if (opacity <= 0) return true;
    final key = (_index, level);
    var snapshot = _snapshots[key];
    if (snapshot == null) {
      snapshot = _renderSnapshot(level);
      if (snapshot == null) return false;
      _snapshots.store(key, snapshot);
    }
    debugUsesSnapshot = true;
    final image = snapshot.image;
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      snapshot.rect,
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, opacity)
        ..filterQuality = FilterQuality.low,
    );
    return true;
  }

  // 播放时每帧都在出图，实时模糊意味着可见的行每帧都要重做一次。
  LyricSnapshot? _renderSnapshot(int level) {
    final layout = _layout!;
    final sigma = level * _blurStepEm * _styles.em;
    final rect = (Offset.zero & size).inflate(sigma * 4);
    final ratio = pixelRatio * _snapshotScale;
    final width = (rect.width * ratio).ceil();
    final height = (rect.height * ratio).ceil();
    if (width <= 0 || height <= 0) return null;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // 模糊半径按像素给，所以图层在缩放之外。
      canvas.saveLayer(
        Offset.zero & Size(width.toDouble(), height.toDouble()),
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma * ratio,
            sigmaY: sigma * ratio,
          ),
      );
      canvas
        ..scale(ratio)
        ..translate(-rect.left, -rect.top);
      layout.main.paint(canvas, Offset.zero);
      layout.translation?.paint(canvas, layout.translationOffset);
      canvas.restore();
      final picture = recorder.endRecording();
      final image = picture.toImageSync(width, height);
      picture.dispose();
      return LyricSnapshot(image, rect);
    } on Object catch (exception, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'alisten',
          context: ErrorDescription('while blurring a lyric line'),
        ),
      );
      return null;
    }
  }

  void _paintBreak(Canvas canvas) {
    final gap = _gap;
    if (gap == null || _selection <= 0) return;
    final dots = breakDotsAt(gap, _clock.positionMs, smooth: _smooth);
    final em = _styles.em;
    final radius = _dotEm * em / 2;
    final color = _styles.main.color!;
    for (var dot = 0; dot < dots.lit.length; dot++) {
      final x = radius + dot * (_dotEm + _dotGapEm) * em;
      canvas.drawCircle(
        Offset(x, lyricBreakHeightEm * em / 2),
        radius * dots.scale,
        Paint()
          ..color = color.withValues(
            alpha: dots.lit[dot] * dots.opacity * _selection,
          ),
      );
    }
  }
}
