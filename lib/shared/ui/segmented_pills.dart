import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';

final class PillSegment<T> {
  const PillSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.showLabels = true,
    super.key,
  });

  final List<PillSegment<T>> segments;
  final T selected;
  final ValueChanged<T>? onChanged;

  /// 为 false 时只显示图标，每段都必须有图标，文字只给读屏。
  final bool showLabels;

  /// 按各段文字只占一行计算。
  static double heightOf(BuildContext context) {
    final label = AlistenTypography.lineHeight(
      _Segment.labelStyle(selected: true),
      MediaQuery.textScalerOf(context),
    );
    final content =
        math.max(AlistenSizes.iconSm, label) + 2 * AlistenSpacing.xs;
    return math.max(AlistenSizes.minTouchTarget, content);
  }

  @override
  Widget build(BuildContext context) {
    assert(
      showLabels || segments.every((segment) => segment.icon != null),
      '只显示图标时每段都要有图标',
    );
    final colors = AlistenColors.of(context);
    final count = segments.length;
    final chosen = segments.indexWhere((segment) => segment.value == selected);
    final onChanged = this.onChanged;
    final pill = BorderRadius.circular(AlistenRadii.pill);
    final track = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassFill,
        borderRadius: pill,
        border: Border.all(color: colors.glassStroke),
      ),
      child: Stack(
        children: [
          if (chosen >= 0)
            Positioned.fill(
              child: AnimatedAlign(
                alignment: Alignment(
                  count == 1 ? 0 : -1 + 2 * chosen / (count - 1),
                  0,
                ),
                duration: AlistenDurations.of(context, AlistenDurations.medium),
                curve: AlistenCurves.emphasized,
                child: FractionallySizedBox(
                  widthFactor: 1 / count,
                  heightFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(AlistenSpacing.xxs),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.selectedFill,
                        borderRadius: pill,
                        // 轮廓标示选中项的边界，与轨道的对比度须达到 3:1。
                        border: Border.all(color: colors.outline),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.shadow
                                .withValues(alpha: 0.12),
                            blurRadius: AlistenSpacing.sm,
                            offset: const Offset(0, AlistenSpacing.xxs / 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (var index = 0; index < count; index++)
                Expanded(
                  child: _Segment(
                    segment: segments[index],
                    selected: index == chosen,
                    showLabel: showLabels,
                    onPressed: onChanged == null
                        ? null
                        : () => onChanged(segments[index].value),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.hasBoundedWidth ? track : IntrinsicWidth(child: track),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.selected,
    required this.showLabel,
    required this.onPressed,
  });

  final PillSegment<T> segment;
  final bool selected;
  final bool showLabel;
  final VoidCallback? onPressed;

  static TextStyle labelStyle({required bool selected}) =>
      AlistenTypography.weighted(
        AlistenTypography.secondary,
        selected ? FontWeight.w700 : FontWeight.w600,
      );

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    // 未选中项也用实色：分段控件常放在玻璃面板里，两层玻璃会提亮背景，半透明
    // 文字不够清晰。选中项靠滑块和字重区分。
    final ink = colors.onGlass;
    final icon = segment.icon;
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      semanticLabel: showLabel ? null : segment.label,
      focusRadius: BorderRadius.circular(AlistenRadii.pill),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: showLabel ? 0 : AlistenSizes.minTouchTarget,
          minHeight: AlistenSizes.minTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlistenSpacing.sm,
            vertical: AlistenSpacing.xs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: AlistenSizes.iconSm, color: ink),
                if (showLabel) const SizedBox(width: AlistenSpacing.xxs),
              ],
              if (showLabel)
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: AlistenDurations.of(
                      context,
                      AlistenDurations.short,
                    ),
                    style: labelStyle(selected: selected).copyWith(color: ink),
                    child: Text(
                      segment.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
