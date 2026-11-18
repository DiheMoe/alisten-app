import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/presentation/media_format.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';

const _padding = EdgeInsetsDirectional.fromSTEB(
  AlistenSpacing.md,
  AlistenSpacing.sm,
  AlistenSpacing.xxs,
  AlistenSpacing.sm,
);

/// 存储的一首歌。平时长按进入多选，“⋯”里打开歌曲页面或删除；多选时点整行
/// 切换选中，“⋯”收起，封面上显示选中标记。
class MediaRow extends StatelessWidget {
  const MediaRow({
    required this.track,
    required this.now,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onOpenLink,
    required this.onDelete,
    super.key,
  });

  final StoredTrack track;
  final DateTime now;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onOpenLink;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final muted = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    return Pressable(
      onPressed: selecting ? onToggle : null,
      onLongPress: selecting ? null : onToggle,
      longPressHint: '多选',
      // 平时点按没有作用，只能长按，读屏不把它当按钮。
      button: selecting,
      selected: selecting ? selected : null,
      child: Padding(
        padding: selecting
            ? _padding.copyWith(end: AlistenSpacing.md)
            : _padding,
        child: Row(
          children: [
            _Cover(track: track, selecting: selecting, selected: selected),
            const SizedBox(width: AlistenSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AlistenTypography.bodyStrong.copyWith(
                      color: colors.onGlass,
                    ),
                  ),
                  const SizedBox(height: AlistenSpacing.xxs / 2),
                  Text(
                    mediaByline(track),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                  Text(
                    mediaDetails(track, now),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ],
              ),
            ),
            if (!selecting)
              ActionMenuButton(
                semanticLabel: '《${track.title}》的更多操作',
                iconSize: AlistenSizes.iconSm,
                entries: [
                  ActionMenuEntry(
                    icon: AlistenIcons.arrowSquareOut,
                    label: '打开歌曲页面',
                    onSelected: onOpenLink,
                  ),
                  ActionMenuEntry(
                    icon: AlistenIcons.trash,
                    label: '删除',
                    danger: true,
                    onSelected: onDelete,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.track,
    required this.selecting,
    required this.selected,
  });

  final StoredTrack track;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cover = CoverArt(url: track.coverUrl, size: AlistenSizes.rowCover);
    if (!selecting) return cover;
    // 品牌色在房间外就是文字色，深色主题下近白：标记一律白色压在暗色上，
    // 有没有封面都看得清。
    return Stack(
      children: [
        cover,
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: selected ? 0.45 : 0.2),
              borderRadius: BorderRadius.circular(AlistenRadii.sm),
            ),
            child: Icon(
              selected ? AlistenIcons.checkCircleFill : AlistenIcons.circle,
              color: Colors.white,
              size: AlistenSizes.icon,
            ),
          ),
        ),
      ],
    );
  }
}

/// 首次读取时的占位行，与 [MediaRow] 同高。
class MediaRowSkeleton extends StatelessWidget {
  const MediaRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final fill = colors.onGlass.withValues(alpha: 0.08);
    final scaler = MediaQuery.textScalerOf(context);
    Widget bar(double width, TextStyle style) => SizedBox(
      height: AlistenTypography.lineHeight(style, scaler),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: width,
          child: Container(
            height: style.fontSize! * 0.8,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(AlistenRadii.pill),
            ),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: Padding(
        padding: _padding.copyWith(end: AlistenSpacing.md),
        child: Row(
          children: [
            Container(
              width: AlistenSizes.rowCover,
              height: AlistenSizes.rowCover,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(AlistenRadii.sm),
              ),
            ),
            const SizedBox(width: AlistenSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(0.55, AlistenTypography.bodyStrong),
                  const SizedBox(height: AlistenSpacing.xxs / 2),
                  bar(0.4, AlistenTypography.secondary),
                  bar(0.75, AlistenTypography.secondary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
