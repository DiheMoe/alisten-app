import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/cover_images.dart';
import 'package:alisten/shared/ui/tracked_hero.dart';
import 'package:flutter/material.dart';

/// 封面只作装饰，读屏跳过它；使用处旁边须有说明同样内容的标题。
class CoverArt extends StatelessWidget {
  const CoverArt({
    required this.url,
    required this.size,
    this.decodeSize,
    this.radius = AlistenRadii.sm,
    this.shadow = false,
    this.heroTag,
    this.placeholderIcon = AlistenIcons.musicNote,
    super.key,
  });

  final String? url;
  final double size;

  /// 默认为 [size]。尺寸带动画的封面应传入动画中的最大尺寸，只解码一次。
  final double? decodeSize;
  final double radius;
  final bool shadow;
  final Object? heroTag;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final shape = BorderRadius.circular(radius);
    final url = this.url;
    // 没有封面时是一块低调的色块，不抢有封面的行。取图途中也是这块颜色，
    // 不是一块和卡片一样白的空白。
    final tint = colors.onGlass.withValues(alpha: 0.08);
    final placeholder = ColoredBox(
      color: tint,
      child: Center(
        child: Icon(
          placeholderIcon,
          size: size <= 64 ? AlistenSizes.iconSm : AlistenSizes.iconLg,
          color: colors.onGlassMuted,
        ),
      ),
    );
    Widget art = url == null || url.isEmpty
        ? placeholder
        : ColoredBox(
            color: tint,
            child: Image(
              image: _imageOf(context, url, decodeSize ?? size),
              width: size,
              height: size,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              frameBuilder: (context, child, frame, synchronous) =>
                  AnimatedOpacity(
                    opacity: synchronous || frame != null ? 1 : 0,
                    duration: AlistenDurations.of(
                      context,
                      AlistenDurations.short,
                    ),
                    curve: AlistenCurves.standard,
                    child: child,
                  ),
              errorBuilder: (_, _, _) => placeholder,
            ),
          );
    art = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: shadow ? colors.coverShadow : null,
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: SizedBox.square(dimension: size, child: art),
      ),
    );
    final heroTag = this.heroTag;
    if (heroTag != null) {
      art = TrackedHero(
        tag: heroTag,
        flightShuttleBuilder: _crossFade,
        child: art,
      );
    }
    return SizedBox.square(dimension: size, child: art);
  }
}

ImageProvider _imageOf(BuildContext context, String url, double size) =>
    ResizeImage(
      CoverImages.of(context, url),
      width: (size * MediaQuery.devicePixelRatioOf(context)).round(),
    );

/// 提前取图并解码，之后同样 [size] 的 [CoverArt] 第一帧就画出封面。取不到
/// 图时界面显示占位，这里不报错。
Future<void> precacheCoverArt(BuildContext context, String url, double size) =>
    precacheImage(_imageOf(context, url, size), context, onError: (_, _) {});

// 飞行中两头的封面交叉淡化：另一头按自己的大小解码的图还没出来时，飞的也一直
// 是有图的封面，不闪底色。上面一层是被打开（或正在关闭）的页面里那一张，随页面
// 出现的程度显出。
Widget _crossFade(
  BuildContext context,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
) {
  final from = (fromContext.widget as Hero).child;
  final to = (toContext.widget as Hero).child;
  final (below, above) = direction == HeroFlightDirection.push
      ? (from, to)
      : (to, from);
  return Stack(
    fit: StackFit.expand,
    children: [
      below,
      FadeTransition(opacity: animation, child: above),
    ],
  );
}
