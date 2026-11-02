import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum TapBeat { short, long }

final class RhythmPattern {
  const RhythmPattern({
    required this.beats,
    required this.onMatched,
    this.holdAfter,
  });

  final List<TapBeat> beats;
  final VoidCallback onMatched;

  /// 非空时，匹配后下一次按下须按住这么久才调用 [onMatched]。
  final Duration? holdAfter;
}

const _ringDiameter = 40.0;

/// 识别在 [child] 上敲出的节奏：按住短于 [longFrom] 为短拍，否则为长拍；按住
/// 达到 [breakAfter] 时作废已敲的拍子，松手超过 [maxGap] 后再按下则从头开始。
/// 匹配前不显示任何内容，也不改变 [child] 的语义。
class TapRhythm extends StatefulWidget {
  const TapRhythm({
    required this.patterns,
    required this.child,
    this.longFrom = const Duration(milliseconds: 350),
    this.breakAfter = const Duration(milliseconds: 1500),
    this.maxGap = const Duration(milliseconds: 1500),
    super.key,
  });

  static const holdProgressKey = ValueKey<String>('tap-rhythm-hold');

  final List<RhythmPattern> patterns;
  final Widget child;
  final Duration longFrom;
  final Duration breakAfter;
  final Duration maxGap;

  @override
  State<TapRhythm> createState() => _TapRhythmState();
}

class _TapRhythmState extends State<TapRhythm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this);

  int? _pointer;
  Offset _downAt = Offset.zero;

  // 当前这次按下是否仍有效；移动、取消、按得过久或按住阶段结束后失效。
  bool _counting = false;
  bool _long = false;
  List<TapBeat> _beats = const [];
  RhythmPattern? _awaitingHold;
  bool _holding = false;

  Timer? _longTimer;
  Timer? _breakTimer;
  Timer? _gapTimer;
  Timer? _holdTimer;

  @override
  void dispose() {
    _cancelTimers();
    _progress.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _downAt = event.position;
    _counting = true;
    _gapTimer?.cancel();
    final hold = _awaitingHold?.holdAfter;
    if (hold != null) {
      _startHold(hold);
      return;
    }
    _long = false;
    _longTimer = Timer(widget.longFrom, () => _long = true);
    _breakTimer = Timer(widget.breakAfter, _reset);
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || !_counting) return;
    if ((event.position - _downAt).distance > kTouchSlop) _reset();
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _longTimer?.cancel();
    _breakTimer?.cancel();
    if (!_counting) return;
    _counting = false;
    if (_holding) {
      _reset();
      return;
    }
    _advance(_long ? TapBeat.long : TapBeat.short);
    if (_beats.isNotEmpty || _awaitingHold != null) {
      _gapTimer = Timer(widget.maxGap, _reset);
    }
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _reset();
  }

  // 不匹配时退回到仍是某个节奏开头的最长后缀：开头多敲的几拍不影响后面的
  // 拍子，无需从头再敲。
  void _advance(TapBeat beat) {
    var beats = [..._beats, beat];
    while (beats.isNotEmpty && !_begins(beats)) {
      beats = beats.sublist(1);
    }
    if (beats.isEmpty) {
      _beats = const [];
      return;
    }
    for (final pattern in widget.patterns) {
      if (listEquals(pattern.beats, beats)) {
        _beats = const [];
        unawaited(HapticFeedback.mediumImpact());
        if (pattern.holdAfter == null) {
          pattern.onMatched();
        } else {
          _awaitingHold = pattern;
        }
        return;
      }
    }
    _beats = beats;
  }

  bool _begins(List<TapBeat> beats) {
    return widget.patterns.any(
      (pattern) =>
          pattern.beats.length >= beats.length &&
          listEquals(pattern.beats.sublist(0, beats.length), beats),
    );
  }

  // 圆环只是进度提示，按住时长由计时器判定，系统移除动画时同样计时。
  void _startHold(Duration hold) {
    _progress.duration = hold;
    if (MediaQuery.disableAnimationsOf(context)) {
      _progress.value = 1;
    } else {
      unawaited(_progress.forward(from: 0));
    }
    _holdTimer = Timer(hold, _held);
    setState(() => _holding = true);
  }

  void _held() {
    final pattern = _awaitingHold;
    unawaited(HapticFeedback.mediumImpact());
    _reset();
    pattern?.onMatched();
  }

  void _reset() {
    _cancelTimers();
    _counting = false;
    _beats = const [];
    _awaitingHold = null;
    if (_holding) {
      _progress.stop();
      setState(() => _holding = false);
    }
  }

  void _cancelTimers() {
    _longTimer?.cancel();
    _breakTimer?.cancel();
    _gapTimer?.cancel();
    _holdTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_holding)
            Positioned.fill(
              key: TapRhythm.holdProgressKey,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: OverflowBox(
                    minWidth: _ringDiameter,
                    maxWidth: _ringDiameter,
                    minHeight: _ringDiameter,
                    maxHeight: _ringDiameter,
                    child: CustomPaint(
                      painter: _RingPainter(
                        progress: _progress,
                        colors: AlistenColors.of(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.colors})
    : super(repaint: progress);

  final Animation<double> progress;
  final AlistenColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = AlistenSizes.progressTrack;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    canvas.drawCircle(
      center,
      size.shortestSide / 2,
      Paint()..color = colors.raised,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, line..color = colors.glassStroke);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.value,
      false,
      line..color = colors.onGlass,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.colors != colors;
  }
}
