import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

const copyTitleHint = '复制歌名';

class TrackRow extends StatelessWidget {
  const TrackRow({
    required this.title,
    this.subtitle,
    this.subtitleLeading,
    this.coverUrl,
    this.trailing,
    this.onPressed,
    this.onLongPress,
    this.longPressHint,
    this.semanticActions,
    this.coverSize = AlistenSizes.rowCover,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AlistenSpacing.page,
      vertical: AlistenSpacing.xs,
    ),
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleLeading;
  final String? coverUrl;
  final Widget? trailing;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? longPressHint;
  final Map<CustomSemanticsAction, VoidCallback>? semanticActions;
  final double coverSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final subtitle = this.subtitle;
    final trailing = this.trailing;
    final row = Padding(
      padding: padding,
      child: Row(
        children: [
          CoverArt(url: coverUrl, size: coverSize),
          const SizedBox(width: AlistenSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AlistenTypography.bodyStrong.copyWith(
                    color: colors.onGlass,
                  ),
                ),
                if (subtitle != null || subtitleLeading != null) ...[
                  const SizedBox(height: AlistenSpacing.xxs / 2),
                  Row(
                    children: [
                      if (subtitleLeading case final leading?) ...[
                        leading,
                        const SizedBox(width: AlistenSpacing.xxs),
                      ],
                      if (subtitle != null)
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AlistenTypography.secondary.copyWith(
                              color: colors.onGlassMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AlistenSpacing.xs),
            trailing,
          ],
        ],
      ),
    );
    final actions = semanticActions;
    if (onPressed == null && onLongPress == null) {
      return Semantics(
        container: true,
        customSemanticsActions: actions,
        child: row,
      );
    }
    return Pressable(
      onPressed: onPressed,
      onLongPress: onLongPress,
      button: onPressed != null,
      longPressHint: longPressHint,
      focusRadius: BorderRadius.circular(AlistenRadii.md),
      child: actions == null
          ? row
          : Semantics(customSemanticsActions: actions, child: row),
    );
  }
}
