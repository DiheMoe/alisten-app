import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:flutter/material.dart';

/// 没有封面时“我喜欢”显示星形，其他显示音符。大于行封面的“我喜欢”有图片时，
/// 角上加一个小星标。星标只作装饰，读屏不读。
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({
    required this.url,
    required this.favorites,
    required this.size,
    this.radius = AlistenRadii.sm,
    this.glow = false,
    super.key,
  });

  final String? url;
  final bool favorites;
  final double size;
  final double radius;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    final cover = CoverArt(
      url: url,
      size: size,
      radius: radius,
      glow: glow,
      placeholderIcon: favorites
          ? Icons.star_rounded
          : Icons.music_note_rounded,
    );
    if (!favorites ||
        url == null ||
        url.isEmpty ||
        size <= AlistenSizes.rowCover) {
      return cover;
    }
    final colors = AlistenColors.of(context);
    return Stack(
      children: [
        cover,
        PositionedDirectional(
          end: AlistenSpacing.xs,
          bottom: AlistenSpacing.xs,
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: colors.brandGradient,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AlistenSpacing.xxs),
                child: Icon(
                  Icons.star_rounded,
                  size: AlistenSizes.inlineIcon,
                  color: colors.onBrand,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 歌单名；“我喜欢”在名字前带一个装饰用的星标。
class PlaylistName extends StatelessWidget {
  const PlaylistName({
    required this.name,
    required this.favorites,
    required this.style,
    this.maxLines = 1,
    this.center = false,
    super.key,
  });

  final String name;
  final bool favorites;
  final TextStyle style;
  final int maxLines;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: style,
    );
    if (!favorites) return text;
    return Row(
      mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.star_rounded,
            size: MediaQuery.textScalerOf(context)
                .scale(style.fontSize ?? AlistenTypography.body.fontSize!),
            color: AlistenColors.of(context).warning,
          ),
        ),
        const SizedBox(width: AlistenSpacing.xxs),
        Flexible(child: text),
      ],
    );
  }
}
