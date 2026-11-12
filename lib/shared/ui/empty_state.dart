import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/widgets.dart';

const _maxWidth = 360.0;

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
    // 一段靠左的文字，不是居中的徽章：标题说发生了什么，说明和按钮说接下来做什么。
    final content = Padding(
      padding: const EdgeInsets.all(AlistenSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: AlistenSizes.icon, color: colors.onGlassMuted),
            const SizedBox(height: AlistenSpacing.sm),
            Text(
              title,
              style: AlistenTypography.title.copyWith(color: colors.onGlass),
            ),
            if (message != null) ...[
              const SizedBox(height: AlistenSpacing.xxs),
              Text(
                message,
                style: AlistenTypography.body.copyWith(
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
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: content,
          );
        }
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
              minWidth: constraints.maxWidth,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: content,
            ),
          ),
        );
      },
    );
  }
}
