import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:flutter/widgets.dart';

enum StatusTone { neutral, success, warning, danger }

class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.icon,
    this.tone = StatusTone.neutral,
    this.busy = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final StatusTone tone;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final ink = switch (tone) {
      StatusTone.neutral => colors.onGlass,
      StatusTone.success => colors.success,
      StatusTone.warning => colors.warning,
      StatusTone.danger => colors.danger,
    };
    const iconSize = AlistenSizes.iconSm - AlistenSpacing.xxs;
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AlistenRadii.pill),
          border: Border.all(color: ink.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlistenSpacing.sm,
            vertical: AlistenSpacing.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                Semantics(
                  value: busySemanticValue,
                  child: BusyIndicator(size: iconSize, color: ink),
                )
              else
                Icon(icon, size: iconSize, color: ink),
              const SizedBox(width: AlistenSpacing.xxs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AlistenTypography.weighted(
                    AlistenTypography.secondary,
                    FontWeight.w700,
                  ).copyWith(color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
