import 'dart:async';

import 'package:alisten/shared/theme/motion.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/widgets.dart';

/// 换页时旧的一页先朝翻页方向移开并淡出，新的一页再从另一侧移入，两页不同时
/// 出现。[page] 变大是往后翻，变小是往回翻；[page] 不变时内容原地更新。
///
/// [onTurned] 在旧的一页淡完、新的一页出现之前调用，列表可以在这时回到顶部。
class PageTurn extends StatefulWidget {
  const PageTurn({
    super.key,
    required this.page,
    required this.child,
    this.onTurned,
  });

  final int page;
  final Widget child;
  final VoidCallback? onTurned;

  @override
  State<PageTurn> createState() => _PageTurnState();
}

class _PageTurnState extends State<PageTurn>
    with SingleTickerProviderStateMixin {
  late final _shown = AnimationController(vsync: this, value: 1);
  late int _page;
  late Widget _child;
  var _forward = true;
  var _leaving = false;

  @override
  void initState() {
    super.initState();
    _page = widget.page;
    _child = widget.child;
  }

  @override
  void didUpdateWidget(PageTurn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page == _page) {
      _child = widget.child;
      return;
    }
    _forward = widget.page > _page;
    if (_leaving) return;
    _leaving = true;
    unawaited(_turn());
  }

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  // 离开途中又换了页时不重新开始：淡完后直接换上最后要的那一页。
  Future<void> _turn() async {
    final whole = AlistenDurations.of(context, AlistenMotion.fadeThrough);
    final out = whole * AlistenMotion.fadeThroughOutShare;
    try {
      await _shown
          .animateBack(0, duration: out, curve: AlistenMotion.fadeOut)
          .orCancel;
      setState(() {
        _leaving = false;
        _page = widget.page;
        _child = widget.child;
      });
      widget.onTurned?.call();
      await _shown
          .animateTo(1, duration: whole - out, curve: AlistenMotion.fadeIn)
          .orCancel;
    } on TickerCanceled {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: _shown,
      child: _child,
      builder: (context, child) {
        final leaves = (_forward ? -1 : 1) * (rtl ? -1 : 1);
        final side = _leaving ? leaves : -leaves;
        return IgnorePointer(
          ignoring: _leaving,
          child: ExcludeSemantics(
            excluding: _leaving,
            child: Opacity(
              opacity: _shown.value,
              child: Transform.translate(
                offset: Offset(
                  (1 - _shown.value) * AlistenMotion.pageTurnShift * side,
                  0,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
