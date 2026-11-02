import 'dart:async';

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/material.dart';

/// 点按浮层外部或系统返回时只调用 [onClose]：这次点按不传给页面，页面也不退出。
class Popover extends StatefulWidget {
  const Popover({
    required this.open,
    required this.onClose,
    required this.content,
    required this.child,
    this.childAnchor = Alignment.topLeft,
    this.contentAnchor = Alignment.bottomLeft,
    this.offset = Offset.zero,
    this.padding = const EdgeInsets.all(AlistenSpacing.xs),
    super.key,
  });

  final bool open;
  final VoidCallback onClose;
  final Widget content;

  /// 应向读屏说明浮层是否展开。展开期间点按它与点按外部一样，只调用 [onClose]。
  final Widget child;
  final Alignment childAnchor;
  final Alignment contentAnchor;
  final Offset offset;
  final EdgeInsetsGeometry padding;

  @override
  State<Popover> createState() => _PopoverState();
}

class _PopoverState extends State<Popover> with SingleTickerProviderStateMixin {
  // 页面构建期间不能显示 overlay 子组件，所以在组件存活期间始终显示；面板只在
  // 展开或收起途中构建。
  final _portal = OverlayPortalController()..show();
  final _link = LayerLink();
  late final AnimationController _motion =
      AnimationController(vsync: this, value: widget.open ? 1 : 0)
        ..addStatusListener((status) {
          if (status.isDismissed) setState(() {});
        });
  late final CurvedAnimation _grow = CurvedAnimation(
    parent: _motion,
    curve: AlistenCurves.bounce,
    reverseCurve: AlistenCurves.exit,
  );
  late final Animation<double> _scale = Tween(
    begin: 0.9,
    end: 1.0,
  ).animate(_grow);
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _motion,
    curve: AlistenCurves.standard,
    reverseCurve: AlistenCurves.exit,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion
      ..duration = AlistenDurations.of(context, AlistenDurations.short)
      ..reverseDuration = AlistenDurations.of(context, AlistenDurations.press);
  }

  @override
  void didUpdateWidget(Popover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    unawaited(widget.open ? _motion.forward() : _motion.reverse());
  }

  @override
  void dispose() {
    _grow.dispose();
    _fade.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.open) widget.onClose();
      },
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => widget.open || !_motion.isDismissed
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    // 接住关闭浮层的点按，不传给页面。与模态遮罩不同，
                    // 读屏仍能访问页面，并多一个关闭入口。
                    if (widget.open)
                      Semantics(
                        container: true,
                        button: true,
                        label: '关闭',
                        onTap: widget.onClose,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTap: widget.onClose,
                        ),
                      ),
                    _buildPanel(context),
                  ],
                )
              : const SizedBox.shrink(),
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final colors = AlistenColors.of(context);
    final shape = BorderRadius.circular(AlistenRadii.md);
    final screen = MediaQuery.sizeOf(context);
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: widget.childAnchor,
        followerAnchor: widget.contentAnchor,
        offset: widget.offset,
        child: IgnorePointer(
          ignoring: !widget.open,
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              alignment: widget.contentAnchor,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: screen.width - 2 * AlistenSpacing.page,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.raised,
                    borderRadius: shape,
                    border: Border.all(color: colors.glassStroke),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.shadow
                            .withValues(alpha: 0.24),
                        blurRadius: AlistenSpacing.xl,
                        offset: const Offset(0, AlistenSpacing.xs),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: shape,
                    child: Padding(
                      padding: widget.padding,
                      child: widget.content,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
