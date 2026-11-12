import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/cover_images.dart';
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
    this.placeholderIcon = Icons.music_note_rounded,
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
    // 没有封面时是一块低调的色块，不抢有封面的行。
    final placeholder = ColoredBox(
      color: colors.onGlass.withValues(alpha: 0.08),
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
            color: colors.glassFill,
            child: Image(
              image: ResizeImage(
                CoverImages.of(context, url),
                width:
                    ((decodeSize ?? size) *
                            MediaQuery.devicePixelRatioOf(context))
                        .round(),
              ),
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
    if (heroTag != null) art = Hero(tag: heroTag, child: art);
    return SizedBox.square(dimension: size, child: art);
  }
}
