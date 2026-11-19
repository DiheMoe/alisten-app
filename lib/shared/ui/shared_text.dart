import 'package:alisten/shared/ui/tracked_hero.dart';
import 'package:flutter/material.dart';

// 飞行前一段里出发那头的文字还在，后一段里落地那头的文字已显出，交叉处两份都
// 不太淡。
const _arriving = Interval(0, 0.6);
const _leaving = Interval(0.4, 1);

/// 在两个页面之间移动的一段文字，比如列表里的歌单名移到歌单页顶部。
///
/// 两头的文字各按自己排好的样子画、缩放到飞行中的外框里，交叉淡化：字号、行数
/// 或内容不同，也是平滑地从一种变成另一种。两头都应只包住文字本身，不撑满一行，
/// 外框才贴着文字移动。
class SharedText extends StatelessWidget {
  const SharedText({required this.tag, required this.child, super.key});

  final Object tag;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      TrackedHero(tag: tag, flightShuttleBuilder: _morph, child: child);
}

Widget _morph(
  BuildContext context,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
) {
  Widget laidOut(BuildContext heroContext) {
    final box = heroContext.findRenderObject();
    return FittedBox(
      child: SizedBox.fromSize(
        size: box is RenderBox && box.hasSize ? box.size : null,
        child: (heroContext.widget as Hero).child,
      ),
    );
  }

  final from = laidOut(fromContext);
  final to = laidOut(toContext);
  // 上面一层是被打开（或正在关闭）的页面里那一份，随页面出现的程度显出。
  final (below, above) = direction == HeroFlightDirection.push
      ? (from, to)
      : (to, from);
  // 飞行中的文字在 Overlay 里，没有页面的 Material，会带上缺少 Material 时的
  // 下划线样式；透明的 Material 给出与页面里相同的文字样式。
  return Material(
    type: MaterialType.transparency,
    child: Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(
          opacity: ReverseAnimation(
            CurvedAnimation(parent: animation, curve: _leaving),
          ),
          child: below,
        ),
        FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: _arriving),
          child: above,
        ),
      ],
    ),
  );
}
