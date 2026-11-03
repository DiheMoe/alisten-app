import 'dart:async';

import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/widgets.dart';

/// 左右滑动切换的模式内容，[pages] 与标签顺序一致。
///
/// 路由是唯一事实源：[page] 来自路由，改变时内容直接跳到该页；滑动停稳在别的
/// 页时只以 [onSettled] 报告，由调用方改路由。松手后的回弹可能拖得很长，
/// [onSettled] 到达时用户也许已经离开或去了别处，调用方要判断是否还该改路由。
/// 点按标签要滑过去时，先调用 [RoomPagerState.glideTo] 再改路由。
class RoomPager extends StatefulWidget {
  const RoomPager({
    required this.pages,
    required this.page,
    required this.onSettled,
    required this.builder,
    this.position,
    super.key,
  });

  final List<RoomMode> pages;
  final RoomMode page;
  final ValueChanged<RoomMode> onSettled;
  final Widget Function(RoomMode mode) builder;

  /// 内容所在的页序号，滑动途中为小数。可能在构建和布局期间更新，监听方只能
  /// 据此重绘。
  final ValueNotifier<double>? position;

  @override
  State<RoomPager> createState() => RoomPagerState();
}

class RoomPagerState extends State<RoomPager> {
  late final PageController _controller = PageController(
    initialPage: widget.pages.indexOf(widget.page),
    // 重新出现时（如从播放器回来）以路由的页为准，不恢复上次停留的页。
    keepPage: false,
  )..addListener(_publish);

  // 点按标签后内容正滑向的页。路由在点按时已经改好，停在这一页时不再报告。
  int? _target;

  // 跟随路由跳页时会以跳页前的位置结束滚动（如手指正按在首页边缘），那不是
  // 用户停下的页；此时又处在构建期间，不能改路由。
  bool _following = false;

  @override
  void initState() {
    super.initState();
    widget.position?.value = widget.pages.indexOf(widget.page).toDouble();
  }

  @override
  void didUpdateWidget(RoomPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page == oldWidget.page || !_controller.hasClients) return;
    final index = widget.pages.indexOf(widget.page);
    if (index == _target || _restsOn(index)) return;
    _target = null;
    _following = true;
    _controller.jumpToPage(index);
    _following = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void glideTo(RoomMode mode) {
    final index = widget.pages.indexOf(mode);
    if (index < 0 || !_controller.hasClients || _restsOn(index)) return;
    _target = index;
    final duration = AlistenDurations.of(context, AlistenDurations.medium);
    // 时长为零的动画会触发断言。
    if (duration == Duration.zero) {
      _controller.jumpToPage(index);
      return;
    }
    unawaited(
      _controller.animateToPage(
        index,
        duration: duration,
        curve: AlistenCurves.emphasized,
      ),
    );
  }

  // 动画刚开始的那一帧还停在起点，不算已在起点那一页。
  bool _restsOn(int index) =>
      !_controller.position.isScrollingNotifier.value &&
      _controller.page == index;

  void _publish() {
    if (_controller.page case final page?) widget.position?.value = page;
  }

  bool _onScrollEnd(ScrollEndNotification notification) {
    if (_following || notification.depth != 0) return false;
    final page = (notification.metrics as PageMetrics).page;
    // 手指按住滑动中的内容时滚动也会结束，此时停在两页之间，等松手后再判断。
    if (page == null || page != page.roundToDouble()) return false;
    final index = page.round();
    final glided = index == _target;
    _target = null;
    final mode = widget.pages[index];
    if (!glided && mode != widget.page) widget.onSettled(mode);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollEndNotification>(
      onNotification: _onScrollEnd,
      child: PageView.custom(
        controller: _controller,
        // 首页和末页之外不能再拉动内容。
        scrollBehavior: ScrollConfiguration.of(context).copyWith(
          overscroll: false,
          scrollbars: false,
          physics: const ClampingScrollPhysics(),
        ),
        childrenDelegate: SliverChildBuilderDelegate(
          (context, index) => widget.builder(widget.pages[index]),
          childCount: widget.pages.length,
          // 离开的页随即释放，如聚焦的聊天输入框不会留着键盘。
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }
}
