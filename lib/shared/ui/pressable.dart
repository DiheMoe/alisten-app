import 'dart:async';

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/widgets.dart';

/// 按下效果在确认不是滚动之后才显示：列表外立即显示，列表内在手指抬起时显示；
/// 至少显示 [AlistenDurations.press]，快速点按也能看到。
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

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _focused = false;
  Timer? _hold;
  bool _lifted = false;

  bool get _enabled => widget.onPressed != null || widget.onLongPress != null;

  void _setDown(bool down) {
    if (_down != down && (_enabled || !down)) setState(() => _down = down);
  }

  void _onTapDown(TapDownDetails _) {
    _hold?.cancel();
    _lifted = false;
    _setDown(true);
    _hold = Timer(AlistenDurations.press, () {
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
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = AlistenDurations.of(context, AlistenDurations.press);
    final opacity = !_enabled && widget.dimWhenDisabled
        ? AlistenPress.disabledOpacity
        : _down
        ? AlistenPress.opacity
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
            onInvoke: (_) => widget.onPressed?.call(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? _onTapDown : null,
          onTapUp: _enabled ? _onTapUp : null,
          onTapCancel: _enabled ? _onTapCancel : null,
          onTap: widget.onPressed,
          onLongPress: _enabled ? widget.onLongPress : null,
          child: AnimatedScale(
            scale: _down ? AlistenPress.scale : 1,
            duration: duration,
            curve: AlistenCurves.standard,
            child: AnimatedOpacity(
              opacity: opacity,
              duration: duration,
              curve: AlistenCurves.standard,
              // 未聚焦时也保留这一层，聚焦时树结构不变，子组件不丢状态。
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: _focused
                    ? BoxDecoration(
                        borderRadius: widget.focusRadius,
                        border: Border.all(
                          color: AlistenColors.of(context).onGlass,
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
    );
  }
}
