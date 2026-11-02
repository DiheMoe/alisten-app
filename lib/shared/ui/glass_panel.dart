import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/widgets.dart';

/// 不模糊背后内容：房间背景整体只模糊一次，比每个面板各自模糊开销小得多。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(AlistenSpacing.md),
    this.radius = AlistenRadii.md,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassFill,
        borderRadius: shape,
        border: Border.all(color: colors.glassStroke),
      ),
      // 内部行的按压效果不超出圆角。
      child: ClipRRect(
        borderRadius: shape,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
