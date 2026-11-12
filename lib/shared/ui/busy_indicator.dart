import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:flutter/material.dart';

const busySemanticValue = '进行中';

const _turn = Duration(milliseconds: 900);
const _arcSweep = math.pi / 2;
const _trackAlpha = 0.2;
const _minStroke = 2.5;

/// 整圈淡色底环上转着一段圆弧：只有一段细弧时，小尺寸下会被看成标点。系统移除
/// 动画时圆弧静止。
///
/// 自身不被读出；周围没有说明正在做什么时传入 [semanticLabel]。
class BusyIndicator extends StatefulWidget {
  const BusyIndicator({
    this.size = 16,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  State<BusyIndicator> createState() => _BusyIndicatorState();
}

class _BusyIndicatorState extends State<BusyIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: _turn,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _turns.stop();
    } else if (!_turns.isAnimating) {
      unawaited(_turns.repeat());
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final spinner = SizedBox.square(
      dimension: size,
      child: RotationTransition(
        turns: _turns,
        child: CustomPaint(
          painter: _SpinnerPainter(
            ink: widget.color ?? AlistenColors.of(context).onGlass,
            stroke: math.max(_minStroke, size / 8),
          ),
        ),
      ),
    );
    final label = widget.semanticLabel;
    if (label == null) return spinner;
    return Semantics(container: true, label: label, child: spinner);
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({required this.ink, required this.stroke});

  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawCircle(
        ring.center,
        ring.width / 2,
        paint..color = ink.withValues(alpha: ink.a * _trackAlpha),
      )
      ..drawArc(ring, -math.pi / 2, _arcSweep, false, paint..color = ink);
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) {
    return oldDelegate.ink != ink || oldDelegate.stroke != stroke;
  }
}
