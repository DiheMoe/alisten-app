import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/widgets.dart';

/// 所在页面停稳后才淡入，页面开始关闭时淡出；拖着页面还没松手时不算关闭。
///
/// 比如歌单页顶部的模糊封面背景：页面长出途中封面单独飞过来，背景这时就画
/// 出来，会在飞行的封面边缘晕出一圈，还跟着外框移动。
class ArrivalFade extends StatefulWidget {
  const ArrivalFade({required this.child, super.key});

  final Widget child;

  @override
  State<ArrivalFade> createState() => _ArrivalFadeState();
}

class _ArrivalFadeState extends State<ArrivalFade> {
  Animation<double>? _route;
  bool _arrived = true;

  // 页面停稳过一次之后，向前才是拖动；之前的向前是正在打开。
  bool _settled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (route == _route) return;
    _route?.removeStatusListener(_onStatus);
    _route = route?..addStatusListener(_onStatus);
    // 此刻读到的“已完成”可能只是路由开始打开前的占位，不算停稳过。
    _arrived = route == null || route.isCompleted;
    _settled = false;
  }

  // 拖动返回时路由进度停在差一点点满的位置，状态是向前，不当作关闭。
  void _onStatus(AnimationStatus status) {
    if (status.isCompleted) _settled = true;
    final arrived = switch (status) {
      AnimationStatus.completed => true,
      AnimationStatus.reverse || AnimationStatus.dismissed => false,
      AnimationStatus.forward => _settled && _arrived,
    };
    if (arrived != _arrived) setState(() => _arrived = arrived);
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 页面刚建好时路由进度还是占位的“已完成”，随后才开始打开：这时直接藏起，
    // 不从显出淡下去。
    return AnimatedOpacity(
      opacity: _arrived ? 1 : 0,
      duration: !_settled
          ? Duration.zero
          : AlistenDurations.of(
              context,
              _arrived ? AlistenDurations.medium : AlistenDurations.short,
            ),
      curve: AlistenCurves.standard,
      child: widget.child,
    );
  }
}
