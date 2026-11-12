import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';

class ChipPill extends StatelessWidget {
  const ChipPill({
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final surface = Theme.of(context).colorScheme.surface;
    final ink = selected ? surface : colors.onGlass;
    final icon = this.icon ?? (selected ? AlistenIcons.checkBold : null);
    final pill = BorderRadius.circular(AlistenRadii.control);
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      focusRadius: pill,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AlistenSizes.minTouchTarget,
        ),
        child: Center(
          widthFactor: 1,
          child: AnimatedContainer(
            duration: AlistenDurations.of(context, AlistenDurations.short),
            curve: AlistenCurves.standard,
            constraints: const BoxConstraints(
              minHeight: AlistenSizes.chipHeight,
            ),
            padding: EdgeInsets.fromLTRB(
              icon == null ? AlistenSpacing.md : AlistenSpacing.sm,
              AlistenSpacing.xxs,
              AlistenSpacing.md,
              AlistenSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: selected ? colors.onGlass : colors.glassFill,
              borderRadius: pill,
              border: Border.all(
                color: selected ? colors.onGlass : colors.glassStroke,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: AlistenSizes.iconSm, color: ink),
                  const SizedBox(width: AlistenSpacing.xxs),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AlistenTypography.weighted(
                      AlistenTypography.secondary,
                      FontWeight.w600,
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
