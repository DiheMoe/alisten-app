import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/material.dart';

/// 头像通常紧挨着成员名字，所以没有 [semanticLabel] 时读屏跳过它。
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    required String this.name,
    this.imageUrl,
    this.size = AlistenSizes.avatar,
    this.ring = false,
    this.semanticLabel,
    super.key,
  }) : icon = null;

  const MemberAvatar.icon(
    IconData this.icon, {
    this.size = AlistenSizes.avatar,
    this.ring = false,
    this.semanticLabel,
    super.key,
  }) : name = null,
       imageUrl = null;

  final String? name;
  final IconData? icon;
  final String? imageUrl;
  final double size;
  final bool ring;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final icon = this.icon;
    final name = this.name?.trim() ?? '';
    final identity = icon == null ? AlistenColors.identity(name) : null;
    final fill = identity?.fill ?? colors.brandGradient;
    final ink = identity?.ink ?? colors.onBrand;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final imageUrl = this.imageUrl;
    Widget avatar = DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: fill),
      child: Center(
        child: icon != null
            ? Icon(icon, size: size / 2, color: ink)
            : Text(
                initial,
                // 首字大小跟随头像，不随系统文字缩放。
                textScaler: TextScaler.noScaling,
                style: AlistenTypography.weighted(
                  AlistenTypography.bodyStrong,
                  FontWeight.w800,
                ).copyWith(fontSize: size * 0.42, height: 1, color: ink),
              ),
      ),
    );
    if (imageUrl != null && imageUrl.isNotEmpty) {
      avatar = Stack(
        fit: StackFit.expand,
        children: [
          avatar,
          ClipOval(
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              excludeFromSemantics: true,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, synchronous) =>
                  AnimatedOpacity(
                    opacity: synchronous || frame != null ? 1 : 0,
                    duration: AlistenDurations.of(
                      context,
                      AlistenDurations.short,
                    ),
                    child: child,
                  ),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }
    avatar = Container(
      width: size,
      height: size,
      foregroundDecoration: ring
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: AlistenSizes.ring,
              ),
            )
          : null,
      child: avatar,
    );
    final label = semanticLabel;
    return label == null
        ? ExcludeSemantics(child: avatar)
        : Semantics(
            image: true,
            label: label,
            child: ExcludeSemantics(child: avatar),
          );
  }
}
