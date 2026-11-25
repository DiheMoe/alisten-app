import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/motion.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/desktop_platform.dart';
import 'package:alisten/shared/ui/tap_origin.dart';
import 'package:alisten/shared/ui/zoom_frame.dart';
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
  final origin = TapOrigin.take();
  // 桌面窗口里从底边升起的面板离鼠标很远，改成窗口正中的对话框。
  if (isDesktopPlatform) {
    final route = _DialogRoute<T>(
      builder: builder,
      dismissible: dismissible,
      barrierColor: AlistenColors.of(context).barrier,
      barrierLabel: localizations.modalBarrierDismissLabel,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    );
    final result = await navigator.push(route);
    if (untilClosed) await route.completed;
    return result;
  }
  final screen = MediaQuery.sizeOf(context);
  final route = _SheetRoute<T>(
    origin: origin != null && sitsLow(origin.rect, screen) ? origin : null,
    builder: builder,
    dismissible: dismissible,
    barrierColor: AlistenColors.of(context).barrier,
    barrierLabel: localizations.modalBarrierDismissLabel,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  final result = await navigator.push(route);
  if (untilClosed) await route.completed;
  return result;
}

/// 以 [result] 结束 [context] 所在的面板。被邀请、分享等面板盖住时也要移除：只
/// pop 会关掉盖在上面的那一个。面板已在关闭时什么都不做，以免弹掉下方的页面。
void dismissSheet(BuildContext context, [Object? result]) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isActive) return;
  if (route.isCurrent) {
    Navigator.of(context).pop(result);
  } else {
    Navigator.of(context).removeRoute(route, result);
  }
}

final class _DialogRoute<T> extends PopupRoute<T> {
  _DialogRoute({
    required this.builder,
    required this.dismissible,
    required this.barrierColor,
    required this.barrierLabel,
    required this.themes,
  });

  final WidgetBuilder builder;
  final bool dismissible;
  final CapturedThemes themes;

  @override
  final Color barrierColor;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => dismissible;

  @override
  Duration get transitionDuration => AlistenDurations.short;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return themes.wrap(
      PopScope<T>(
        canPop: dismissible,
        child: _DialogCard(child: Builder(builder: builder)),
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
    final curve = CurveTween(curve: AlistenCurves.standard);
    return FadeTransition(
      opacity: animation.drive(curve),
      child: ScaleTransition(
        scale: animation.drive(Tween(begin: 0.96, end: 1.0).chain(curve)),
        child: child,
      ),
    );
  }
}

class _DialogCard extends StatelessWidget {
  const _DialogCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final media = MediaQuery.of(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: MaterialLocalizations.of(context).dialogLabel,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AlistenSpacing.xl,
          AlistenSpacing.xl,
          AlistenSpacing.xl,
          AlistenSpacing.xl + media.viewInsets.bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AlistenSizes.sheetMaxWidth,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: colors.raised,
                borderRadius: BorderRadius.circular(AlistenRadii.lg),
                border: Border.all(color: colors.glassStroke),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: DefaultTextStyle.merge(
                  style: AlistenTypography.body.copyWith(color: colors.onGlass),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AlistenSpacing.page),
                    child: child,
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

/// 从被点的元素长出、缩回去；没有起点时以 UIKit 的面板弹簧从底部升起。拖动时
/// 由 [SheetPanel] 移动卡片，进度只表示遮罩的深浅。
final class _SheetRoute<T> extends PopupRoute<T> {
  _SheetRoute({
    required this.origin,
    required this.builder,
    required this.dismissible,
    required this.barrierColor,
    required this.barrierLabel,
    required this.themes,
  });

  final LaunchOrigin? origin;
  final WidgetBuilder builder;
  final bool dismissible;
  final CapturedThemes themes;

  // 拖动松手关闭时带上手指的速度，以路由进度每秒计。
  double? _releaseVelocity;

  // 松手关闭时的进度；关闭途中外框从拖动后的位置缩回起点。
  double? _shrinkFrom;

  @override
  final Color barrierColor;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => dismissible;

  // 转场由弹簧驱动，框架不用它计时。
  @override
  Duration get transitionDuration => const Duration(milliseconds: 600);

  bool get _reduced {
    final context = navigator?.context;
    return context != null &&
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
  }

  @override
  Simulation? createSimulation({required bool forward}) {
    final target = forward ? 1.0 : 0.0;
    final velocity = _releaseVelocity ?? 0;
    _releaseVelocity = null;
    if (_reduced) return settledAt(target);
    final spring = origin == null
        ? AlistenSprings.sheet
        : forward
        ? AlistenSprings.zoomOpen
        : AlistenSprings.zoomClose;
    return springTo(
      spring,
      from: controller!.value,
      to: target,
      velocity: velocity,
    );
  }

  /// 拖动松手关闭：记下此刻的进度，带着手指速度从这里缩回起点。[velocity]
  /// 以外框长出的程度每秒计，向关闭方向为负。
  void _releaseFrom(double velocity) {
    final shown = controller!.value;
    _shrinkFrom = shown;
    _releaseVelocity = velocity * shown;
  }

  /// 内容拒绝关闭：留在原位。
  void _keep() {
    _shrinkFrom = null;
    _releaseVelocity = null;
    _settle(0);
  }

  /// 外框长出的程度；[held] 为 true 时卡片正被拖着或在弹回，外框保持全尺寸。
  double _growthOf(double shown, {required bool held}) {
    final from = _shrinkFrom;
    if (from != null) return from <= 0 ? 0 : shown / from;
    return held ? 1 : shown;
  }

  /// 起点：元素现在的位置；关闭时元素已不在屏幕上或移到了上半部分，就从
  /// 底部退出。
  Rect? _startRect(Size screen, {required bool closing}) {
    final origin = this.origin;
    if (origin == null) return null;
    final now = origin.current;
    if (now != null &&
        now.overlaps(Offset.zero & screen) &&
        sitsLow(now, screen)) {
      return now;
    }
    return closing ? null : origin.rect;
  }

  void _follow(double progress) => controller!.value = progress.clamp(0, 1);

  void _settle(double velocity) {
    if (_reduced) {
      controller!.value = 1;
      return;
    }
    controller!.animateWith(
      springTo(
        AlistenSprings.sheet,
        from: controller!.value,
        to: 1,
        velocity: velocity,
      ),
    );
  }

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
  ) => child;
}

// 向上拖过原位时最多拉出 100，与任务页一致。
const _liftExtent = 100.0;

class SheetPanel extends StatefulWidget {
  const SheetPanel({required this.child, this.dismissible = true, super.key});

  final Widget child;
  final bool dismissible;

  @override
  State<SheetPanel> createState() => _SheetPanelState();
}

class _SheetPanelState extends State<SheetPanel>
    with SingleTickerProviderStateMixin {
  // 关闭阈值按卡片高度计算；跟手按外层（铺满全屏，就是路由滑动的距离）计算。
  final _card = GlobalKey();
  double _drag = 0;
  bool _dragging = false;

  // 拖动时卡片的位移，向下为正；向上拖过原位时是橡皮筋拉出的距离。
  late final _pull = AnimationController.unbounded(vsync: this);

  // 内容暂不可关闭时面板不跟手，只累计拖动距离：拖到关闭位置松手时仍询问
  // 内容，内容可借此请用户确认。
  double? _heldDrag;

  bool get _closable =>
      ModalRoute.of(context)?.popDisposition != RoutePopDisposition.doNotPop;

  _SheetRoute<Object?>? get _route => switch (ModalRoute.of(context)) {
    final _SheetRoute<Object?> route => route,
    _ => null,
  };

  double get _travel => context.size?.height ?? 1;

  bool _closes(double drag, DragEndDetails details) => sheetCloses(
    drag: drag,
    velocity: details.velocity.pixelsPerSecond.dy,
    height: _card.currentContext?.size?.height ?? double.infinity,
  );

  void _onDragStart(DragStartDetails details) {
    _dragging = _closable;
    _heldDrag = _dragging ? null : 0;
    _drag = 0;
    _pull.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_heldDrag case final held?) {
      _heldDrag = math.max(0, held + details.delta.dy);
      return;
    }
    if (!_dragging) return;
    _drag += details.delta.dy;
    if (_drag < 0) {
      _pull.value = -rubberBand(-_drag, _liftExtent);
      _route?._follow(1);
    } else {
      _pull.value = _drag;
      _route?._follow(1 - _drag / _travel);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_heldDrag case final held?) {
      _heldDrag = null;
      if (_closes(held, details)) {
        unawaited(Navigator.of(context).maybePop());
      }
      return;
    }
    if (!_dragging) return;
    _dragging = false;
    final speed = details.velocity.pixelsPerSecond.dy;
    final velocity = -speed / _travel;
    if (_drag > 0 && _closes(_drag, details)) {
      unawaited(_close(velocity));
    } else {
      _settlePull(speed);
      _route?._settle(velocity);
    }
  }

  Future<void> _close(double velocity) async {
    final route = _route;
    route?._releaseFrom(velocity);
    final closed = await Navigator.of(context).maybePop();
    // 拖动途中内容变为不可关闭时 maybePop 不会关闭面板，需把它移回原位。
    if (!closed && mounted) {
      route?._keep();
      _settlePull(0);
    }
  }

  void _onDragCancel() {
    _heldDrag = null;
    if (!_dragging) return;
    _dragging = false;
    _settlePull(0);
    _route?._settle(0);
  }

  /// 把卡片弹回原位；[velocity] 是像素每秒，向下为正。
  void _settlePull(double velocity) {
    if (_pull.value == 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pull.value = 0;
      return;
    }
    unawaited(
      _pull.animateWith(
        springTo(
          AlistenSprings.sheet,
          from: _pull.value,
          to: 0,
          velocity: velocity,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pull.dispose();
    super.dispose();
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
            child: _Zoom(
              route: _route,
              pull: _pull,
              dragging: () => _dragging,
              radius: shape,
              fill: colors.raised,
              child: Container(
                key: _card,
                decoration: BoxDecoration(
                  color: colors.raised,
                  borderRadius: shape,
                  border: Border.all(color: colors.glassStroke),
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  type: MaterialType.transparency,
                  child: DefaultTextStyle.merge(
                    style: AlistenTypography.body.copyWith(
                      color: colors.onGlass,
                    ),
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
      ),
    );
  }
}

/// 卡片的外框：从起点长出、缩回，拖动时跟着位移。
class _Zoom extends StatelessWidget {
  const _Zoom({
    required this.route,
    required this.pull,
    required this.dragging,
    required this.radius,
    required this.fill,
    required this.child,
  });

  final _SheetRoute<Object?>? route;
  final Animation<double> pull;
  final bool Function() dragging;
  final BorderRadius radius;
  final Color fill;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = this.route;
    final screen = MediaQuery.sizeOf(context);
    final shownBy = route?.animation;
    return AnimatedBuilder(
      animation: Listenable.merge([?shownBy, pull]),
      child: child,
      builder: (context, card) {
        final value = shownBy?.value ?? 1;
        final closing =
            route?._shrinkFrom != null ||
            shownBy?.status == AnimationStatus.reverse;
        final growth =
            route?._growthOf(value, held: dragging() || pull.value != 0) ?? 1;
        final from = route?._startRect(screen, closing: closing);
        // 从元素长出时内容淡入淡出；从底部升起时一直是实的。
        final fades = from != null;
        final solid = fades ? morphSolid(growth) : 1.0;
        final shown = fades ? morphContent(growth, closing: closing) : 1.0;
        return ZoomFrame(
          growth: growth,
          from: from,
          riseBy: screen.height,
          fromRadius: route?.origin?.radius ?? radius.topLeft.x,
          toRadius: radius,
          clipAtRest: false,
          fill: fill.withValues(alpha: fill.a * solid),
          offset: Offset(0, pull.value),
          child: Opacity(
            opacity: shown,
            alwaysIncludeSemantics: !closing,
            child: card,
          ),
        );
      },
    );
  }
}
