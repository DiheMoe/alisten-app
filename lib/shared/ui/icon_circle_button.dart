import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';

enum IconCircleButtonStyle {
  glass,
  plain,

  /// 只用于一组控件中唯一的主控件，例如播放和暂停。
  solid,
  brand,
}

/// 无论 [diameter] 多大，触控区域至少 48×48。
class IconCircleButton extends StatelessWidget {
  const IconCircleButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.style = IconCircleButtonStyle.glass,
    this.diameter = AlistenSizes.iconButton,
    this.iconSize = AlistenSizes.icon,
    this.expanded,
    this.image,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final IconCircleButtonStyle style;
  final double diameter;
  final double iconSize;
  final bool? expanded;

  /// 加载成功后淡入并取代 [icon]，加载中和失败时显示 [icon]。读屏只读
  /// [semanticLabel]。
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final (fill, gradient, border, ink) = switch (style) {
      IconCircleButtonStyle.glass => (
        colors.glassFill,
        null,
        Border.all(color: colors.glassStroke),
        colors.onGlass,
      ),
      IconCircleButtonStyle.plain => (null, null, null, colors.onGlass),
      IconCircleButtonStyle.solid => (
        colors.onGlass,
        null,
        null,
        Theme.of(context).colorScheme.surface,
      ),
      IconCircleButtonStyle.brand => (
        null,
        colors.brandGradient,
        null,
        colors.onBrand,
      ),
    };
    final target = diameter < AlistenSizes.minTouchTarget
        ? AlistenSizes.minTouchTarget
        : diameter;
    final glyph = Icon(icon, size: iconSize, color: ink);
    final image = this.image;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      expanded: expanded,
      focusRadius: BorderRadius.circular(target / 2),
      child: SizedBox.square(
        dimension: target,
        child: Center(
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              gradient: gradient,
              border: border,
              boxShadow: style == IconCircleButtonStyle.solid
                  ? [
                      BoxShadow(
                        color: colors.glow.withValues(alpha: 0.35),
                        blurRadius: diameter / 2,
                        offset: Offset(0, diameter / 10),
                      ),
                    ]
                  : null,
            ),
            child: image == null
                ? glyph
                : Image(
                    image: ResizeImage.resizeIfNeeded(
                      (diameter * MediaQuery.devicePixelRatioOf(context))
                          .round(),
                      null,
                      image,
                    ),
                    width: diameter,
                    height: diameter,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    gaplessPlayback: true,
                    frameBuilder: (context, child, frame, synchronous) {
                      final loaded = synchronous || frame != null;
                      return AnimatedSwitcher(
                        duration: AlistenDurations.of(
                          context,
                          AlistenDurations.short,
                        ),
                        // 前后两个子组件的键必须不同，否则图标立即消失，不会淡出。
                        child: KeyedSubtree(
                          key: ValueKey(loaded),
                          child: loaded ? ClipOval(child: child) : glyph,
                        ),
                      );
                    },
                    errorBuilder: (_, _, _) => glyph,
                  ),
          ),
        ),
      ),
    );
  }
}
