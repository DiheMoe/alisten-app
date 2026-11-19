import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/avatar_images.dart';
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
    final fill = identity?.fill ?? colors.brand;
    final ink = identity?.ink ?? colors.onBrand;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final imageUrl = this.imageUrl;
    Widget avatar = DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
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
            child: Image(
              image: avatarImageOf(context, imageUrl),
              fit: BoxFit.cover,
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

/// 头像不论画多大都按最大的一档解码，同一个人的头像只解码一次：在一处出现
/// 过，换到另一处（比如从大厅进设置）第一帧就有图，不先露出首字。
ImageProvider avatarImageOf(BuildContext context, String url) =>
    ResizeImage.resizeIfNeeded(
      (AlistenSizes.profileAvatar * MediaQuery.devicePixelRatioOf(context))
          .round(),
      null,
      AvatarImages.of(context, url),
    );

/// 提前解码头像，之后 [MemberAvatar] 第一帧就画出图片。没设头像的成员取图会
/// 失败，界面显示首字，这里不报错。
Future<void> precacheMemberAvatar(BuildContext context, String imageUrl) =>
    precacheImage(
      avatarImageOf(context, imageUrl),
      context,
      onError: (_, _) {},
    );
