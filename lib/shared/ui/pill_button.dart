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
    this.glow = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final PillButtonStyle style;
  final bool busy;
  final bool large;
  final bool expand;

  /// 只对 [PillButtonStyle.primary] 生效。
  final bool glow;

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
    final ink = primary ? colors.onBrand : colors.onGlass;
    final iconSize = large ? AlistenSizes.icon : AlistenSizes.iconSm;
    final leading = busy
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
      focusRadius: BorderRadius.circular(AlistenRadii.pill),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: large
              ? AlistenSizes.largeTouchTarget
              : AlistenSizes.minTouchTarget,
          minWidth: AlistenSizes.minTouchTarget,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AlistenRadii.pill),
            gradient: primary ? colors.brandGradient : null,
            color: style == PillButtonStyle.secondary ? colors.glassFill : null,
            border: style == PillButtonStyle.secondary
                ? Border.all(color: colors.glassStroke)
                : null,
            boxShadow: glow && primary
                ? [
                    BoxShadow(
                      color: colors.glow.withValues(alpha: 0.45),
                      blurRadius: AlistenSpacing.xl,
                      offset: const Offset(0, AlistenSpacing.xs),
                    ),
                  ]
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
                if (leading != null) ...[
                  leading,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
