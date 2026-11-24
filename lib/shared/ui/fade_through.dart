import 'dart:ui' show lerpDouble;

import 'package:alisten/shared/theme/motion.dart';
import 'package:flutter/widgets.dart';

/// 用作 `AnimatedSwitcher.transitionBuilder`，配合 [AlistenMotion.fadeThrough]
/// 的时长，用于加载中、列表、结果这类整块替换。淡出途中的内容不接收触摸也不被
/// 读出，已经离开的按钮不会被再点一次。
Widget fadeThrough(Widget child, Animation<double> animation) =>
    _fadeThrough(child, animation, Alignment.center);

/// 同 [fadeThrough]，新内容从 [alignment] 处放大。顶部对齐的内容从顶部放大，
/// 切换途中新旧内容的顶边不错开。
AnimatedSwitcherTransitionBuilder fadeThroughFrom(Alignment alignment) =>
    (child, animation) => _fadeThrough(child, animation, alignment);

Widget _fadeThrough(
  Widget child,
  Animation<double> animation,
  Alignment alignment,
) {
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final leaving = !animation.status.isForwardOrCompleted;
      final double opacity;
      final double scale;
      if (leaving) {
        final out = ((1 - animation.value) / AlistenMotion.fadeThroughOutShare)
            .clamp(0.0, 1.0);
        opacity = 1 - AlistenMotion.fadeOut.transform(out);
        scale = 1;
      } else {
        final into =
            ((animation.value - AlistenMotion.fadeThroughOutShare) /
                    (1 - AlistenMotion.fadeThroughOutShare))
                .clamp(0.0, 1.0);
        final eased = AlistenMotion.fadeIn.transform(into);
        opacity = eased;
        scale = lerpDouble(AlistenMotion.fadeThroughFrom, 1, eased)!;
      }
      return IgnorePointer(
        ignoring: leaving,
        child: ExcludeSemantics(
          excluding: leaving,
          // 新内容等旧内容淡完才出现，这段时间里读屏也要能找到它。
          child: Opacity(
            opacity: opacity,
            alwaysIncludeSemantics: !leaving,
            child: Transform.scale(
              scale: scale,
              alignment: alignment,
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
