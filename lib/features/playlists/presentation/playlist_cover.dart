import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:flutter/material.dart';

/// 歌单在列表里和歌单页顶部共有的封面、名字和那行说明，打开时各自飞到对应
/// 的位置。
typedef PlaylistHeroTags = ({Object cover, Object name, Object facts});

PlaylistHeroTags myPlaylistHeroTags(String id) => (
  cover: ('my-playlist-cover', id),
  name: ('my-playlist-name', id),
  facts: ('my-playlist-facts', id),
);

/// 没有封面时“我喜欢”显示星形，其他显示音符。大于行封面的“我喜欢”有图片时，
/// 角上加一个小星标。星标只作装饰，读屏不读。
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({
    required this.url,
    required this.favorites,
    required this.size,
    this.radius = AlistenRadii.sm,
    this.shadow = false,
    this.heroTag,
    super.key,
  });

  final String? url;
  final bool favorites;
  final double size;
  final double radius;
  final bool shadow;

  /// 见 [PlaylistHeroTags]。
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    final cover = CoverArt(
      url: url,
      size: size,
      radius: radius,
      shadow: shadow,
      heroTag: heroTag,
      placeholderIcon: favorites
          ? AlistenIcons.starFill
          : AlistenIcons.musicNote,
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
                color: colors.brand,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AlistenSpacing.xxs),
                child: Icon(
                  AlistenIcons.starFill,
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
    // 只占文字和星标那么宽，在页面之间移动时外框贴着它们，见 SharedText。
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            AlistenIcons.starFill,
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
