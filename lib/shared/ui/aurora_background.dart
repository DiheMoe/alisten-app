import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/visible_frames.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

const _darkStrength = 0.42;
const _lightStrength = 0.3;

// 用定时器而非 Ticker 驱动：Ticker 按屏幕刷新率出帧，120 Hz 屏上静止的房间页
// 也会持续满帧重绘。光斑大而柔和、转得很慢，约 30 帧/秒已足够平滑。
const _frameInterval = Duration(milliseconds: 33);

class _AuroraBackgroundState extends State<AuroraBackground>
    with WidgetsBindingObserver, VisibleFrames {
  final _drift = ValueNotifier<double>(0);
  Timer? _timer;
  // 只累计实际漂移的时长，暂停后恢复不会跳变。
  Duration _drifted = Duration.zero;

  bool _colourful = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colourful = AlistenColors.of(context).aurora
        .any((color) => HSLColor.fromColor(color).saturation > 0.05);
    if (colourful != _colourful) {
      _colourful = colourful;
      visibleFramesChanged();
    }
  }

  @override
  void visibleFramesChanged() {
    // 没有色相的光斑（界面自己的黑白灰）漂移起来看不出变化，不为它出帧。
    final drifting =
        onScreen && !keyboardUp && !animationsRemoved && _colourful;
    final timer = _timer;
    if (drifting == (timer != null)) return;
    if (timer == null) {
      _timer = Timer.periodic(_frameInterval, _advance);
    } else {
      _drifted += _frameInterval * timer.tick;
      timer.cancel();
      _timer = null;
    }
  }

  // `tick` 包含错过的周期，相位跟随真实经过的时间，回调延迟不会拖慢转速。
  void _advance(Timer timer) {
    final drifted = _drifted + _frameInterval * timer.tick;
    final loop = AlistenDurations.auroraLoop.inMicroseconds;
    _drift.value = drifted.inMicroseconds % loop / loop;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _AuroraPainter(
            drift: _drift,
            colors: AlistenColors.of(context).aurora,
            strength: theme.brightness == Brightness.dark
                ? _darkStrength
                : _lightStrength,
          ),
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.drift,
    required this.colors,
    required this.strength,
  }) : super(repaint: drift);

  final ValueListenable<double> drift;
  final List<Color> colors;
  final double strength;

  // 每圈的转数必须是整数，一圈结束时首尾才能衔接。
  static const _turnsAcross = [1, -1, 1];
  static const _turnsDown = [2, 1, -1];
  static const _phases = [0.0, 2.1, 4.2];

  @override
  void paint(Canvas canvas, Size size) {
    final angle = drift.value * 2 * math.pi;
    for (var light = 0; light < colors.length && light < 3; light++) {
      final phase = _phases[light];
      final center = Offset(
        size.width *
            (0.5 + 0.42 * math.sin(_turnsAcross[light] * angle + phase)),
        size.height *
            (0.34 + 0.26 * math.cos(_turnsDown[light] * angle + phase * 1.3)),
      );
      final radius = size.width * (0.75 + 0.12 * math.sin(angle + phase));
      final color = colors[light];
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: strength),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) {
    return !identical(oldDelegate.drift, drift) ||
        !listEquals(oldDelegate.colors, colors) ||
        oldDelegate.strength != strength;
  }
}
