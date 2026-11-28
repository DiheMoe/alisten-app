import 'dart:async';
import 'dart:ui' as ui show Image;
import 'dart:ui' show ImageFilter;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/motion.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/drop.dart';
import 'package:alisten/shared/ui/morph_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// 外框长到 0.3 之后阴影才出现，到 0.8 时全深。
const _shadowFrom = 0.3;
const _shadowSpan = 0.5;

// 收起的最后 0.12 秒里，缩回按钮大小的底色淡出。
const _fadeOutFrom = 0.76;

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
    this.pours = false,
    this.fromPoint = false,
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

  /// 浮层盖在按钮上展开时设为 true：菜单像一滴液体从按钮倒出来，收起时
  /// 流回按钮，见 [Pour]。
  final bool pours;

  /// 为 true 时浮层从锚点长出，而不是从 [child] 的外形变过去。
  final bool fromPoint;

  @override
  State<Popover> createState() => _PopoverState();
}

/// 打开时菜单从触发按钮的外形变出来：外框按弹簧从按钮的矩形长到菜单的矩形，
/// 先是胶囊，0.07 秒后圆角收成卡片；内容随外框缩放，从模糊变清晰。收起时反过来：
/// 内容先模糊淡去，外框缩回按钮，最后按钮大小的底色淡出，共 0.5 秒。
class _PopoverState extends State<Popover> with TickerProviderStateMixin {
  // 页面构建期间不能显示 overlay 子组件，所以在组件存活期间始终显示；面板只在
  // 展开或收起途中构建。
  final _portal = OverlayPortalController()..show();
  final _link = LayerLink();

  // 弹簧会冲过终点，不能限制在 0 到 1 之间。在 initState 里按创建时的状态
  // 定起点：延迟初始化会等到第一次打开时才取值，起点就成了已经打开。
  late final AnimationController _growth;
  late final AnimationController _corners;
  late final _dismissal =
      AnimationController(vsync: this, duration: AlistenMotion.menuDismiss)
        ..addStatusListener((status) {
          if (status.isCompleted) setState(() => _closing = false);
        });
  Timer? _squaring;
  bool _closing = false;
  Size _trigger = Size.zero;

  // 液滴：按钮的样子，按钮被它代替、藏起来；还没开完就收起时停在的那一刻。
  final _source = GlobalKey();
  ui.Image? _glyph;
  PourOut? _returnFrom;

  bool get _shown => widget.open || _closing;

  bool get _pours => widget.pours && !reducedMotion(context);

  @override
  void initState() {
    super.initState();
    final value = widget.open ? 1.0 : 0.0;
    _growth = AnimationController.unbounded(vsync: this, value: value);
    _corners = AnimationController.unbounded(vsync: this, value: value);
    if (widget.pours) Goo.load();
  }

  @override
  void didUpdateWidget(Popover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    widget.open ? _grow() : _shrink();
  }

  void _measureTrigger() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) _trigger = box.size;
  }

  // 按钮刚画过，拍下它的样子；拍不到就不藏按钮，菜单只是盖住它。
  void _snapshot() {
    if (!_pours || _closing) return;
    final boundary = _source.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return;
    _glyph?.dispose();
    _glyph = null;
    try {
      _glyph = boundary.toImageSync(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    } on Object {
      _glyph = null;
    }
  }

  PourOut _opening() => PourOut(
    progress: _growth.value,
    time: _seconds(_growth.lastElapsedDuration) ?? 1,
    squared: _corners.value,
  );

  static double? _seconds(Duration? duration) =>
      duration == null ? null : duration.inMicroseconds / 1e6;

  void _grow() {
    _snapshot();
    _closing = false;
    _returnFrom = null;
    _dismissal.value = 0;
    _squaring?.cancel();
    _measureTrigger();
    if (reducedMotion(context)) {
      _growth.value = 1;
      _corners.value = 1;
      return;
    }
    unawaited(
      _growth.animateWith(
        springTo(
          AlistenSprings.menuOpen,
          from: _growth.value,
          to: 1,
          velocity: _growth.velocity,
        ),
      ),
    );
    _corners.stop();
    _squaring = Timer(AlistenMotion.menuCornersDelay, () {
      unawaited(
        _corners.animateWith(
          springTo(AlistenSprings.menuCorners, from: _corners.value, to: 1),
        ),
      );
    });
  }

  void _shrink() {
    _squaring?.cancel();
    _measureTrigger();
    _returnFrom = _growth.value < 1 || _growth.isAnimating ? _opening() : null;
    if (reducedMotion(context)) {
      _growth.value = 0;
      _corners.value = 0;
      return;
    }
    _closing = true;
    unawaited(
      _growth.animateWith(
        springTo(
          AlistenSprings.menuClose,
          from: _growth.value,
          to: 0,
          velocity: _growth.velocity,
        ),
      ),
    );
    unawaited(
      _corners.animateWith(
        springTo(AlistenSprings.menuClose, from: _corners.value, to: 0),
      ),
    );
    unawaited(_dismissal.forward(from: 0));
  }

  @override
  void dispose() {
    _squaring?.cancel();
    _growth.dispose();
    _corners.dispose();
    _dismissal.dispose();
    _glyph?.dispose();
    super.dispose();
  }

  // 液滴此刻在倒出还是在收回；停稳后为 null，菜单就是普通的卡片。
  Pour? get _pour {
    if (!_pours) return null;
    if (_closing) {
      return PourBack(
        time: _dismissal.value * returnSeconds,
        from: _returnFrom,
      );
    }
    final settled =
        !_growth.isAnimating && _growth.value >= 1 && _corners.value >= 1;
    return settled ? null : _opening();
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
          overlayChildBuilder: (context) => _shown
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
          child: widget.pours ? _triggerInPlace() : widget.child,
        ),
      ),
    );
  }

  // 液滴代替按钮的时候按钮藏起来，读屏仍能读到它。
  Widget _triggerInPlace() => Opacity(
    opacity: _shown && _glyph != null && _pours ? 0 : 1,
    alwaysIncludeSemantics: true,
    child: RepaintBoundary(key: _source, child: widget.child),
  );

  Widget _buildPanel(BuildContext context) {
    final colors = AlistenColors.of(context);
    final screen = MediaQuery.sizeOf(context);
    final shadow = Theme.of(context).colorScheme.shadow.withValues(alpha: 0.24);
    // 在按钮处是透明的，长大才成为卡片：按钮上不会先冒出、最后又留下一块灰。
    final tint = colors.raised.withValues(alpha: 0);
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
          child: AnimatedBuilder(
            animation: Listenable.merge([_growth, _corners, _dismissal]),
            child: Padding(padding: widget.padding, child: widget.content),
            builder: (context, content) {
              final pour = _pour;
              final grown = _growth.value;
              final solid = morphSolid(grown);
              // 阴影向下偏移、范围大，外框还只有按钮大小时会在按钮下面
              // 留一团灰影；长到三成以上才投下阴影，缩回时也先收掉。
              final lifted = ((grown - _shadowFrom) / _shadowSpan).clamp(
                0.0,
                1.0,
              );
              final shown =
                  pour?.reveal ?? morphContent(grown, closing: _closing);
              final blur =
                  pour?.contentBlur ??
                  AlistenMotion.menuContentBlur *
                      ((1 - grown) / 0.4).clamp(0.0, 1.0);
              // 液滴自己淡去。
              final opacity = _closing && pour == null
                  ? (1 - (_dismissal.value - _fadeOutFrom) / (1 - _fadeOutFrom))
                        .clamp(0.0, 1.0)
                  : 1.0;
              return Opacity(
                opacity: opacity,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: screen.width - 2 * AlistenSpacing.page,
                  ),
                  child: MorphPanel(
                    growth: grown,
                    corners: _corners.value,
                    trigger: widget.fromPoint ? Size.zero : _trigger,
                    triggerAnchor: widget.childAnchor,
                    panelAnchor: widget.contentAnchor,
                    offset: widget.offset,
                    radius: AlistenRadii.md,
                    // 液滴按自己的进度淡入淡出底色、阴影和描边。
                    fill: pour != null
                        ? colors.raised
                        : lerpPremultiplied(tint, colors.raised, solid),
                    border: colors.glassStroke.withValues(
                      alpha: colors.glassStroke.a * (pour != null ? 1 : solid),
                    ),
                    shadow: BoxShadow(
                      color: shadow.withValues(
                        alpha: shadow.a * (pour != null ? 1 : lifted),
                      ),
                      blurRadius: AlistenSpacing.xl,
                      offset: const Offset(0, AlistenSpacing.xs),
                    ),
                    pour: pour,
                    glyph: _glyph,
                    child: Opacity(
                      opacity: shown,
                      child: ImageFiltered(
                        enabled: blur > 0.01,
                        imageFilter: ImageFilter.blur(
                          sigmaX: blur,
                          sigmaY: blur,
                        ),
                        child: content,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
