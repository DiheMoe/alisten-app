import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:flutter/cupertino.dart';

/// 须放在使用 [pullRefreshPhysics] 的 `CustomScrollView` 中，作为第一个 sliver
/// 或紧跟吸顶头部：下拉指示依赖列表顶部可越界。读屏用户无法下拉，页面需另设
/// 刷新入口。
class SliverPullRefresh extends StatelessWidget {
  const SliverPullRefresh({required this.onRefresh, super.key});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return CupertinoSliverRefreshControl(
      refreshTriggerPullDistance: AlistenSizes.refreshPull,
      refreshIndicatorExtent: AlistenSizes.refreshHold,
      onRefresh: onRefresh,
      builder: _indicator,
    );
  }

  static Widget _indicator(
    BuildContext context,
    RefreshIndicatorMode mode,
    double pulledExtent,
    double triggerDistance,
    double holdExtent,
  ) {
    if (mode == RefreshIndicatorMode.inactive) return const SizedBox.shrink();
    final colors = AlistenColors.of(context);
    final pulled = (pulledExtent / triggerDistance).clamp(0.0, 1.0);
    // 拉到位后持续转圈直到指示器收回，收回途中不再显示箭头。
    final busy = mode != RefreshIndicatorMode.drag;
    return Center(
      child: Opacity(
        opacity:
            mode == RefreshIndicatorMode.armed ||
                mode == RefreshIndicatorMode.refresh
            ? 1
            : pulled,
        child: Container(
          width: AlistenSizes.iconButton,
          height: AlistenSizes.iconButton,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.raised,
            border: Border.all(color: colors.glassStroke),
          ),
          child: Center(
            child: busy
                ? const BusyIndicator(
                    size: AlistenSizes.iconSm,
                    semanticLabel: '正在刷新',
                  )
                : Transform.rotate(
                    angle: pulled * math.pi,
                    child: Icon(
                      AlistenIcons.arrowDown,
                      size: AlistenSizes.iconSm,
                      color: colors.onGlass,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 顶部始终可越界以拉出 [SliverPullRefresh]；末端保持平台行为：默认回弹的平台
/// 照常回弹，其余平台由 [PullRefreshScrollPhysics] 截住。
ScrollPhysics pullRefreshPhysics(BuildContext context) {
  const parent = AlwaysScrollableScrollPhysics();
  final platform = ScrollConfiguration.of(context).getScrollPhysics(context);
  return platform is BouncingScrollPhysics
      ? const BouncingScrollPhysics(parent: parent)
      : const PullRefreshScrollPhysics(parent: parent);
}

/// 顶部回弹；末端像 clamp 一样截住并报告越界，Android 上仍由系统显示末端的
/// 拉伸效果。只应经 [pullRefreshPhysics] 按平台选用。
class PullRefreshScrollPhysics extends BouncingScrollPhysics {
  const PullRefreshScrollPhysics({super.parent});

  @override
  PullRefreshScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return PullRefreshScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final end = position.maxScrollExtent;
    if (end <= position.pixels && position.pixels < value) {
      return value - position.pixels;
    }
    if (position.pixels < end && end < value) return value - end;
    return 0;
  }
}
