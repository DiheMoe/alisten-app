import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:flutter/material.dart';

const busySemanticValue = '进行中';

/// 圆弧不提供语义：系统移除动画时它以 0.75 的进度静止，会被读成百分比。周围
/// 没有说明正在做什么时传入 [semanticLabel]。
class BusyIndicator extends StatelessWidget {
  const BusyIndicator({
    this.size = 16,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final arc = ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CircularProgressIndicator(
          value: still ? 0.75 : null,
          strokeWidth: size / 8,
          strokeCap: StrokeCap.round,
          color: color ?? AlistenColors.of(context).onGlass,
          backgroundColor: Colors.transparent,
        ),
      ),
    );
    final label = semanticLabel;
    if (label == null) return arc;
    return Semantics(container: true, label: label, child: arc);
  }
}
