import 'dart:async';

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/motion.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/desktop_platform.dart';
import 'package:alisten/shared/ui/hover_glow.dart';
import 'package:alisten/shared/ui/tap_origin.dart';
import 'package:flutter/widgets.dart';

/// 桌面窗口里鼠标指着时的样子。
enum PressableHover {
  /// 整块淡淡亮起：按钮、标签、列表里的一行。
  tint,

  /// 光跟着指针走，靠近指针的边缘也亮起来。只给卡片这样的大块用，用多了
  /// 满屏都在闪。
  glow,
}

/// 按下时在控件上叠一层墨迹，形状同 [focusRadius]，不缩放也不变淡。墨迹在确认
/// 不是滚动之后才出现：列表外立即出现，列表内在手指抬起时出现；至少保持
/// [AlistenMotion.pressHold]，快速点按也能看到。
///
/// [onPressed] 和 [onLongPress] 都为 null 时才禁用。
class Pressable extends StatefulWidget {
  const Pressable({
    required this.child,
    required this.onPressed,
    this.onLongPress,
    this.longPressHint,
    this.semanticLabel,
    this.button = true,
    this.selected,
    this.toggled,
    this.inMutuallyExclusiveGroup = false,
    this.expanded,
    this.dimWhenDisabled = true,
    this.focusRadius = const BorderRadius.all(Radius.circular(AlistenRadii.sm)),
    this.focusNode,
    this.ink = true,
    this.hover = PressableHover.tint,
    this.hoverColor,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? longPressHint;
  final String? semanticLabel;

  /// 开关类控件应设为 false，改设 [toggled]。
  final bool button;
  final bool? selected;
  final bool? toggled;
  final bool inMutuallyExclusiveGroup;
  final bool? expanded;
  final bool dimWhenDisabled;
  final BorderRadius focusRadius;
  final FocusNode? focusNode;

  /// 为 false 时按下不叠墨迹，比如点开菜单的按钮：菜单从它长出来就是反馈。
  final bool ink;

  final PressableHover hover;

  /// 鼠标指着时亮起的颜色，默认是玻璃上的文字色。填了深色的按钮要给浅色，
  /// 否则看不出亮了。
  final Color? hoverColor;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final _ink = AnimationController(vsync: this);
  bool _down = false;
  bool _focused = false;
  Timer? _hold;
  bool _lifted = false;

  bool get _enabled => widget.onPressed != null || widget.onLongPress != null;

  // 先记下自己的位置：接下来打开的页面或面板从这里长出。
  void _press() {
    final onPressed = widget.onPressed;
    if (onPressed == null) return;
    TapOrigin.record(context, radius: widget.focusRadius.topLeft.x);
    onPressed();
  }

  void _setDown(bool down) {
    if (!widget.ink) return;
    if (_down == down || (!_enabled && down)) return;
    _down = down;
    final reduced = reducedMotion(context);
    unawaited(
      down
          ? _ink.animateTo(
              1,
              duration: reduced ? Duration.zero : AlistenMotion.pressInk,
            )
          : _ink.animateTo(
              0,
              duration: reduced ? Duration.zero : AlistenMotion.pressRelease,
              curve: AlistenMotion.pressReleaseCurve,
            ),
    );
  }

  void _onTapDown(TapDownDetails _) {
    _hold?.cancel();
    _lifted = false;
    _setDown(true);
    _hold = Timer(AlistenMotion.pressHold, () {
      _hold = null;
      if (_lifted) _setDown(false);
    });
  }

  void _onTapUp(TapUpDetails _) {
    _lifted = true;
    if (_hold == null) _setDown(false);
  }

  void _onTapCancel() {
    _hold?.cancel();
    _hold = null;
    _setDown(false);
  }

  @override
  void didUpdateWidget(Pressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) {
      _hold?.cancel();
      _hold = null;
      _down = false;
      _ink.value = 0;
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _ink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final opacity = !_enabled && widget.dimWhenDisabled
        ? AlistenPress.disabledOpacity
        : 1.0;
    return Semantics(
      container: true,
      button: widget.button,
      enabled: _enabled,
      selected: widget.selected,
      toggled: widget.toggled,
      inMutuallyExclusiveGroup: widget.inMutuallyExclusiveGroup,
      expanded: widget.expanded,
      label: widget.semanticLabel,
      onLongPressHint: widget.onLongPress == null ? null : widget.longPressHint,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: _enabled,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _press(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? _onTapDown : null,
          onTapUp: _enabled ? _onTapUp : null,
          onTapCancel: _enabled ? _onTapCancel : null,
          onTap: widget.onPressed == null ? null : _press,
          onLongPress: _enabled ? widget.onLongPress : null,
          // 鼠标没有长按的习惯，右键做同一件事。
          onSecondaryTap: isDesktopPlatform && _enabled
              ? widget.onLongPress
              : null,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: AlistenDurations.of(context, AlistenDurations.short),
            curve: AlistenCurves.standard,
            // 墨迹和焦点框两层一直都在，按下或聚焦时树结构不变，子组件不丢状态。
            child: _lit(
              colors,
              AnimatedBuilder(
                animation: _ink,
                builder: (context, child) => DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    color: _ink.value == 0
                        ? null
                        : colors.onGlass.withValues(
                            alpha: AlistenMotion.pressInkAlpha * _ink.value,
                          ),
                    borderRadius: widget.focusRadius,
                  ),
                  child: child,
                ),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: _focused
                      ? BoxDecoration(
                          borderRadius: widget.focusRadius,
                          border: Border.all(
                            color: colors.onGlass,
                            width: AlistenSizes.ring,
                          ),
                        )
                      : const BoxDecoration(),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 桌面窗口里鼠标指着时亮起来。
  Widget _lit(AlistenColors colors, Widget child) {
    if (!isDesktopPlatform || !widget.ink) return child;
    return HoverGlow(
      radius: widget.focusRadius,
      color: widget.hoverColor ?? colors.onGlass,
      enabled: _enabled,
      follow: widget.hover == PressableHover.glow,
      child: child,
    );
  }
}
