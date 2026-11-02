import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/material.dart';

/// 面板推入根导航器，盖住包括迷你播放条在内的所有页面。[dismissible] 为 false
/// 时只能由内容自行关闭；内容暂不可关闭时（如表单提交中）用 `canPop: false`
/// 的 `PopScope` 表示，遮罩、返回键和拖动把手都会遵守，并同样调用它的
/// `onPopInvokedWithResult`。
///
/// [untilClosed] 为 true 时等收起动画结束才返回。面板收起期间若移除它下方的
/// 页面，Navigator 会直接移除、不播放退出动画；需要在面板关闭后离开当前页面时
/// 才等待。
Future<T?> showSheetPanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  bool untilClosed = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final localizations = MaterialLocalizations.of(context);
  final route = _SheetRoute<T>(
    builder: builder,
    dismissible: dismissible,
    barrierColor: AlistenColors.of(context).barrier,
    barrierLabel: localizations.modalBarrierDismissLabel,
    duration: AlistenDurations.of(context, AlistenDurations.medium),
    reverseDuration: AlistenDurations.of(context, AlistenDurations.short),
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  final result = await navigator.push(route);
  if (untilClosed) await route.completed;
  return result;
}

final class _SheetRoute<T> extends PopupRoute<T> {
  _SheetRoute({
    required this.builder,
    required this.dismissible,
    required this.barrierColor,
    required this.barrierLabel,
    required this.duration,
    required this.reverseDuration,
    required this.themes,
  });

  final WidgetBuilder builder;
  final bool dismissible;
  final Duration duration;
  final Duration reverseDuration;
  final CapturedThemes themes;

  @override
  final Color barrierColor;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => dismissible;

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => reverseDuration;

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: animation!,
    curve: AlistenCurves.standard,
    reverseCurve: AlistenCurves.exit,
  );
  late final Animation<Offset> _rise = Tween(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(_curve);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return themes.wrap(
      PopScope<T>(
        canPop: dismissible,
        child: SheetPanel(
          dismissible: dismissible,
          child: Builder(builder: builder),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(position: _rise, child: child);
  }

  @override
  void dispose() {
    _curve.dispose();
    super.dispose();
  }
}

const _dismissShare = 0.3;
const _dismissVelocity = 700.0;

class SheetPanel extends StatefulWidget {
  const SheetPanel({required this.child, this.dismissible = true, super.key});

  final Widget child;
  final bool dismissible;

  @override
  State<SheetPanel> createState() => _SheetPanelState();
}

class _SheetPanelState extends State<SheetPanel> {
  // 关闭阈值按卡片高度计算；外层铺满全屏，不能用它的高度。
  final _card = GlobalKey();
  double _drag = 0;
  bool _dragging = false;

  // 内容暂不可关闭时面板不跟手，只累计拖动距离：拖到关闭位置松手时仍询问
  // 内容，内容可借此请用户确认。
  double? _heldDrag;

  bool get _closable =>
      ModalRoute.of(context)?.popDisposition != RoutePopDisposition.doNotPop;

  void _onDragStart(DragStartDetails details) {
    _dragging = _closable;
    _heldDrag = _dragging ? null : 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_heldDrag case final held?) {
      _heldDrag = math.max(0, held + details.delta.dy);
      return;
    }
    if (!_dragging) return;
    setState(() => _drag = math.max(0, _drag + details.delta.dy));
  }

  bool _farEnough(double drag, DragEndDetails details) {
    final height = _card.currentContext?.size?.height ?? double.infinity;
    return drag > height * _dismissShare ||
        details.velocity.pixelsPerSecond.dy > _dismissVelocity;
  }

  void _onDragEnd(DragEndDetails details) {
    if (_heldDrag case final held?) {
      _heldDrag = null;
      if (_farEnough(held, details)) {
        unawaited(Navigator.of(context).maybePop());
      }
      return;
    }
    if (!_dragging) return;
    final close = _farEnough(_drag, details);
    setState(() {
      _dragging = false;
      if (!close) _drag = 0;
    });
    if (close) unawaited(_close());
  }

  Future<void> _close() async {
    await Navigator.of(context).maybePop();
    // 拖动途中内容变为不可关闭时 maybePop 不会关闭面板，需把它移回原位。
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      setState(() => _drag = 0);
    }
  }

  void _onDragCancel() {
    _heldDrag = null;
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _drag = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final localizations = MaterialLocalizations.of(context);
    final media = MediaQuery.of(context);
    final shape = BorderRadius.circular(AlistenRadii.lg);
    final handle = SizedBox(
      height: AlistenSizes.minTouchTarget,
      width: double.infinity,
      child: Align(
        alignment: const Alignment(0, -0.5),
        child: Container(
          width: AlistenSizes.sheetHandle.width,
          height: AlistenSizes.sheetHandle.height,
          decoration: BoxDecoration(
            color: colors.onGlass.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(AlistenRadii.pill),
          ),
        ),
      ),
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: localizations.bottomSheetLabel,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AlistenSpacing.xs,
          media.padding.top + AlistenSpacing.xl,
          AlistenSpacing.xs,
          AlistenSpacing.xs + media.viewInsets.bottom,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AlistenSizes.sheetMaxWidth,
            ),
            child: AnimatedContainer(
              key: _card,
              duration: _dragging
                  ? Duration.zero
                  : AlistenDurations.of(context, AlistenDurations.short),
              curve: AlistenCurves.standard,
              transform: Matrix4.translationValues(0, _drag, 0),
              decoration: BoxDecoration(
                color: colors.raised,
                borderRadius: shape,
                border: Border.all(color: colors.glassStroke),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: DefaultTextStyle.merge(
                  style: AlistenTypography.body.copyWith(color: colors.onGlass),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.dismissible)
                        Semantics(
                          button: true,
                          label: localizations.closeButtonLabel,
                          onTap: () =>
                              unawaited(Navigator.of(context).maybePop()),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragStart: _onDragStart,
                            onVerticalDragUpdate: _onDragUpdate,
                            onVerticalDragEnd: _onDragEnd,
                            onVerticalDragCancel: _onDragCancel,
                            child: handle,
                          ),
                        )
                      else
                        ExcludeSemantics(child: handle),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            AlistenSpacing.page,
                            0,
                            AlistenSpacing.page,
                            // 键盘弹出时面板位于键盘之上，
                            // 此时 `padding.bottom` 为 0。
                            AlistenSpacing.page + media.padding.bottom,
                          ),
                          child: widget.child,
                        ),
                      ),
                    ],
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
