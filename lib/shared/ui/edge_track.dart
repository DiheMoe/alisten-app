import 'dart:math' as math;
import 'dart:ui';

/// 贴着圆角卡片上边缘的一条线：从左侧顺着左上圆角弯上来，沿上边走，再顺着
/// 右上圆角弯下去，像描在卡片边框上。
///
/// 坐标以卡片左上角为原点。线离卡片边缘 [inset]，两端各沿圆角弯 [sweep] 弧度。
/// 进度按沿线的长度推进，经过圆角时和在直线上一样快。
final class EdgeTrack {
  const EdgeTrack({
    required this.width,
    required this.radius,
    required this.inset,
    this.sweep = math.pi / 2,
  });

  final double width;
  final double radius;
  final double inset;
  final double sweep;

  double get _arc => radius - inset;
  double get _corner => sweep * _arc;
  double get _straight => math.max(width - 2 * radius, 0);

  double get length => 2 * _corner + _straight;

  // 正上方的角度：y 轴向下，角度顺时针增大。
  static const _up = 3 * math.pi / 2;

  /// 从起点沿线走 [distance] 到达的点。
  Offset pointAt(double distance) {
    final along = distance.clamp(0.0, length);
    final arc = _arc;
    if (along < _corner) {
      final angle = _up - sweep + along / arc;
      return Offset(radius, radius) +
          Offset(math.cos(angle), math.sin(angle)) * arc;
    }
    if (along < _corner + _straight) {
      return Offset(radius + along - _corner, inset);
    }
    final angle = _up + math.min((along - _corner - _straight) / arc, sweep);
    return Offset(width - radius, radius) +
        Offset(math.cos(angle), math.sin(angle)) * arc;
  }

  Path get path => Path()
    ..arcTo(
      Rect.fromCircle(center: Offset(radius, radius), radius: _arc),
      _up - sweep,
      sweep,
      true,
    )
    ..lineTo(width - radius, inset)
    ..arcTo(
      Rect.fromCircle(center: Offset(width - radius, radius), radius: _arc),
      _up,
      sweep,
      false,
    );

  /// 从起点到 [distance] 的那一段。
  Path upTo(double distance) {
    final contours = path.computeMetrics().iterator;
    if (!contours.moveNext()) return Path();
    final line = contours.current;
    return line.extractPath(0, distance.clamp(0.0, line.length));
  }
}
