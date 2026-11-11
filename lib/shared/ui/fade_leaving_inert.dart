import 'package:flutter/widgets.dart';

/// 用作 `AnimatedSwitcher.transitionBuilder`：淡出途中的内容不接收触摸也不被
/// 读出，已经离开的按钮（如“重试”“创建”）不会被再点一次。
Widget fadeLeavingInert(Widget child, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final leaving = !animation.status.isForwardOrCompleted;
      return IgnorePointer(
        ignoring: leaving,
        child: ExcludeSemantics(excluding: leaving, child: child),
      );
    },
    child: FadeTransition(opacity: animation, child: child),
  );
}
