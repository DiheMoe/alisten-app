import 'dart:ui' as ui;

import 'package:alisten/shared/theme/motion.dart';
import 'package:alisten/shared/ui/desktop_platform.dart';
import 'package:flutter/widgets.dart';

const _fadeIn = Duration(milliseconds: 120);
const _fadeOut = Duration(milliseconds: 240);

// 整块亮起时的深浅，是按下时墨迹的一半。
const _tintAlpha = AlistenMotion.pressInkAlpha / 2;

// 光跟着指针时：整个控件薄薄亮一层，指针处最亮，指针附近的边缘也跟着亮。
const _baseAlpha = 0.025;
const _glowAlpha = 0.065;
const _rimAlpha = 0.2;

// 光照多远随控件的大小变：小按钮整个亮起，大卡片只亮指针周围。
const _reachShare = 0.7;
const _minReach = 64.0;
const _maxReach = 240.0;

const _popScale = 1.1;
const _coverZoom = 1.03;
const _coverSheenAlpha = 0.08;

/// 鼠标指着控件时亮起：淡入，离开后淡出，形状同 [radius]。
class HoverGlow extends StatefulWidget {
  const HoverGlow({
    required this.radius,
    required this.color,
    required this.enabled,
    required this.follow,
    required this.child,
    this.paint = true,
    super.key,
  });

  final BorderRadius radius;
  final Color color;

  /// 为 true 时光跟着指针走，指针处最亮；否则整块一样亮。
  final bool follow;

  /// 为 false 时不在外框上画光，只把悬停进度传给子组件（如 [HoverCover]）。
  final bool paint;

  /// 不能按的控件不亮。
  final bool enabled;
  final Widget child;

  /// 所在的控件亮起的程度，0 到 1；不在 [HoverGlow] 里时为 null。
  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HoverScope>()?.shown;

  @override
  State<HoverGlow> createState() => _HoverGlowState();
}

class _HoverGlowState extends State<HoverGlow>
    with SingleTickerProviderStateMixin {
  late final _shown = AnimationController(vsync: this);
  final _pointer = ValueNotifier(Offset.zero);
  bool _lit = false;

  void _light(PointerEvent event) {
    _pointer.value = event.localPosition;
    if (_lit) return;
    _lit = true;
    _shown.animateTo(
      1,
      duration: reducedMotion(context) ? Duration.zero : _fadeIn,
      curve: Curves.easeOut,
    );
  }

  void _dim() {
    if (!_lit) return;
    _lit = false;
    _shown.animateBack(
      0,
      duration: reducedMotion(context) ? Duration.zero : _fadeOut,
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(HoverGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _dim();
  }

  @override
  void dispose() {
    _shown.dispose();
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.paint
        ? CustomPaint(
            foregroundPainter: _GlowPainter(
              shown: _shown,
              pointer: widget.follow ? _pointer : null,
              radius: widget.radius,
              color: widget.color,
            ),
            child: widget.child,
          )
        : widget.child;
    return MouseRegion(
      opaque: false,
      onEnter: widget.enabled ? _light : null,
      onHover: widget.enabled && widget.paint && widget.follow ? _light : null,
      onExit: (_) => _dim(),
      child: _HoverScope(shown: _shown, child: content),
    );
  }
}

class _HoverScope extends InheritedWidget {
  const _HoverScope({required this.shown, required super.child});

  final Animation<double> shown;

  @override
  bool updateShouldNotify(_HoverScope oldWidget) => oldWidget.shown != shown;
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.shown,
    required this.pointer,
    required this.radius,
    required this.color,
  }) : super(repaint: Listenable.merge([shown, pointer]));

  final Animation<double> shown;

  /// 为 null 时整块一样亮。
  final ValueNotifier<Offset>? pointer;
  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strength = shown.value;
    if (strength <= 0) return;
    final shape = radius.toRRect(Offset.zero & size);
    final pointer = this.pointer;
    if (pointer == null) {
      canvas.drawRRect(
        shape,
        Paint()..color = color.withValues(alpha: _tintAlpha * strength),
      );
      return;
    }
    final reach = (size.longestSide * _reachShare).clamp(_minReach, _maxReach);
    ui.Gradient around(double alpha) => ui.Gradient.radial(
      pointer.value,
      reach,
      [color.withValues(alpha: alpha * strength), color.withValues(alpha: 0)],
    );
    canvas
      ..drawRRect(
        shape,
        Paint()..color = color.withValues(alpha: _baseAlpha * strength),
      )
      ..drawRRect(shape, Paint()..shader = around(_glowAlpha))
      ..drawRRect(
        shape.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = around(_rimAlpha),
      );
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) =>
      oldDelegate.shown != shown ||
      oldDelegate.pointer != pointer ||
      oldDelegate.radius != radius ||
      oldDelegate.color != color;
}

/// 鼠标指着所在的控件时略微放大，轻轻一弹。只用在图标这样不含文字的小东西
/// 上：缩放途中文字每一帧都得按新的大小重画。
class HoverPop extends StatelessWidget {
  const HoverPop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    final shown = HoverGlow.maybeOf(context);
    if (shown == null || reducedMotion(context)) return child;
    return ScaleTransition(
      scale: shown
          .drive(CurveTween(curve: Curves.easeOutBack))
          .drive(Tween(begin: 1, end: _popScale)),
      child: child,
    );
  }
}

/// 封面卡片的悬停反馈：只提亮并略微放大封面。要放在 [HoverGlow] 里面。
class HoverCover extends StatelessWidget {
  const HoverCover({required this.radius, required this.child, super.key});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    final shown = HoverGlow.maybeOf(context);
    if (shown == null) return child;
    final zoomed = reducedMotion(context)
        ? child
        : ScaleTransition(
            scale: shown
                .drive(CurveTween(curve: Curves.easeOutCubic))
                .drive(Tween(begin: 1, end: _coverZoom)),
            child: child,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AnimatedBuilder(
        animation: shown,
        builder: (context, child) => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            color: shown.value == 0
                ? null
                : const Color(0xFFFFFFFF)
                      .withValues(alpha: _coverSheenAlpha * shown.value),
          ),
          child: child,
        ),
        child: zoomed,
      ),
    );
  }
}
