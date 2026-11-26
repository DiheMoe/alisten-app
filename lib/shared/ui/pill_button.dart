import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';

enum PillButtonStyle {
  /// 只用于页面或面板中唯一的主操作。
  primary,
  secondary,
  ghost,
}

class PillButton extends StatelessWidget {
  const PillButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = PillButtonStyle.primary,
    this.busy = false,
    this.large = false,
    this.expand = false,
    this.expanded,
    this.danger = false,
    this.iconAfter = false,
    super.key,
  }) : assert(!danger || style != PillButtonStyle.primary, '危险色的文字放在品牌色填充上看不清');

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final PillButtonStyle style;
  final bool busy;
  final bool large;
  final bool expand;

  final bool? expanded;

  /// 删除这类不能撤回的操作：文字和图标用危险色。不能与 primary 同用。
  final bool danger;

  /// 为 true 时图标在文字之后，比如“下一页 ›”。
  final bool iconAfter;

  /// 同一个按钮换一种尺寸，供排版它的容器按平台决定。
  PillButton sized({required bool large, required bool expand}) => PillButton(
    key: key,
    label: label,
    onPressed: onPressed,
    icon: icon,
    style: style,
    busy: busy,
    large: large,
    expand: expand,
    expanded: expanded,
    danger: danger,
    iconAfter: iconAfter,
  );

  /// 按标签只占一行计算。
  static double heightOf(BuildContext context, {bool large = false}) {
    final style = AlistenTypography.bodyStrong;
    final label =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    final icon = large ? AlistenSizes.icon : AlistenSizes.iconSm;
    final content = math.max(icon, label) + 2 * AlistenSpacing.xs;
    final minimum = large
        ? AlistenSizes.largeTouchTarget
        : AlistenSizes.minTouchTarget;
    return math.max(minimum, content);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final primary = style == PillButtonStyle.primary;
    final ink = primary
        ? colors.onBrand
        : danger
        ? colors.danger
        : colors.onGlass;
    final iconSize = large ? AlistenSizes.icon : AlistenSizes.iconSm;
    final glyph = busy
        ? Semantics(
            value: busySemanticValue,
            child: BusyIndicator(size: iconSize * 0.8, color: ink),
          )
        : icon == null
        ? null
        : Icon(icon, size: iconSize, color: ink);
    return Pressable(
      onPressed: busy ? null : onPressed,
      // 忙碌不等于不可用，不变淡。
      dimWhenDisabled: !busy,
      hoverColor: primary ? colors.onBrand : null,
      expanded: expanded,
      focusRadius: BorderRadius.circular(AlistenRadii.control),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: large
              ? AlistenSizes.largeTouchTarget
              : AlistenSizes.minTouchTarget,
          minWidth: AlistenSizes.minTouchTarget,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AlistenRadii.control),
            color: switch (style) {
              PillButtonStyle.primary => colors.brand,
              PillButtonStyle.secondary => colors.glassFill,
              PillButtonStyle.ghost => null,
            },
            border: style == PillButtonStyle.secondary
                ? Border.all(color: colors.glassStroke)
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: large ? AlistenSpacing.xl : AlistenSpacing.lg,
              vertical: AlistenSpacing.xs,
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (glyph != null && !iconAfter) ...[
                  glyph,
                  const SizedBox(width: AlistenSpacing.xs),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AlistenTypography.weighted(
                      AlistenTypography.bodyStrong,
                      FontWeight.w700,
                    ).copyWith(color: ink),
                  ),
                ),
                if (glyph != null && iconAfter) ...[
                  const SizedBox(width: AlistenSpacing.xs),
                  glyph,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
