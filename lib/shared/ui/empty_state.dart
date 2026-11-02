import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/widgets.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final message = this.message;
    final action = this.action;
    final content = Padding(
      padding: const EdgeInsets.all(AlistenSpacing.page),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AlistenSizes.emptyBadge,
            height: AlistenSizes.emptyBadge,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.glassFill,
              border: Border.all(color: colors.glassStroke),
              boxShadow: [
                BoxShadow(
                  color: colors.glow.withValues(alpha: 0.3),
                  blurRadius: AlistenSpacing.xxxl,
                ),
              ],
            ),
            child: Icon(icon, size: AlistenSizes.iconLg, color: colors.onGlass),
          ),
          const SizedBox(height: AlistenSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AlistenTypography.bodyStrong.copyWith(color: colors.onGlass),
          ),
          if (message != null) ...[
            const SizedBox(height: AlistenSpacing.xxs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AlistenTypography.secondary.copyWith(
                color: colors.onGlassMuted,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AlistenSpacing.lg),
            action,
          ],
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return Center(child: content);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
              minWidth: constraints.maxWidth,
            ),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}
