import 'package:flutter/widgets.dart';

/// [duration] 为 0（系统移除动画）时直接换成新尺寸：时长为 0 的 `AnimatedSize`
/// 会在自身布局中再次标记布局，触发框架断言。
class AnimatedResize extends StatelessWidget {
  const AnimatedResize({
    required this.duration,
    required this.child,
    this.curve = Curves.linear,
    this.alignment = Alignment.center,
    super.key,
  });

  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: alignment,
      child: child,
    );
  }
}
