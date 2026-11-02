import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:flutter/material.dart';

class InlineMessage extends StatelessWidget {
  const InlineMessage({
    required this.text,
    this.tone = StatusTone.danger,
    this.action,
    super.key,
  });

  final String text;
  final StatusTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final (ink, icon) = switch (tone) {
      StatusTone.neutral => (colors.onGlass, Icons.info_rounded),
      StatusTone.success => (colors.success, Icons.check_circle_rounded),
      StatusTone.warning => (colors.warning, Icons.warning_rounded),
      StatusTone.danger => (colors.danger, Icons.error_rounded),
    };
    final action = this.action;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ink.withValues(alpha: AlistenTint.fill),
        borderRadius: BorderRadius.circular(AlistenRadii.sm),
        border: Border.all(color: ink.withValues(alpha: AlistenTint.stroke)),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          AlistenSpacing.sm,
          AlistenSpacing.sm,
          action == null ? AlistenSpacing.sm : AlistenSpacing.xxs,
          AlistenSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(icon, size: AlistenSizes.iconSm, color: ink),
            const SizedBox(width: AlistenSpacing.xs),
            Expanded(
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  text,
                  style: AlistenTypography.weighted(
                    AlistenTypography.secondary,
                    FontWeight.w600,
                  ).copyWith(color: ink),
                ),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
