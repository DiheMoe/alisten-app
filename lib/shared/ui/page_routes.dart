import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/motion.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/tap_origin.dart';
import 'package:alisten/shared/ui/zoom_frame.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

// 拖动距离加上 0.35 秒的速度投影达到 0.4665 宽度就返回；超过每秒 1.5 宽度的
// 甩动，松手速度最多放大到 4.25 倍。
const _popReach = 0.4665;
const _popLead = 0.35;
const _flickSpeed = 1.5;
const _flickBoost = 4.25;
const _dragBackSlop = 30.0;

// 页面向左最多拉出半个宽度，任务页向上最多拉出 100。
const _pageRubberReach = 0.5;
const _taskRubberExtent = 100.0;

// 任务页顶部露出后面的页面。
const _taskGap = 10.0;
const _taskCorner = Radius.circular(38);

// 拖动中让路由停在差一点点满的位置：状态不是“完成”，底下的页面才继续绘制。
const _almostShown = 0.9999;

// 从入口卡片长出时，卡片的快照在外框长到这一段之前淡去，页面内容在这一段里
// 淡入；缩回时页面内容在外框缩到这一段之前淡去，快照在这一段里淡入，落在卡片
// 上时正好是卡片的样子。
const _pictureGoneBy = 0.35;
const _contentFrom = 0.05;
const _contentSpan = 0.3;
const _pictureBackFrom = 0.4;
const _contentGoneBy = 0.3;

// 被普通导航盖住时，底下的页面跟着向左移开这一份宽度。
const _pushParallax = 0.3;

// 普通导航推入的页面左边缘投下的阴影。
const _pushShadowAlpha = 0.16;
const _pushShadowBlur = 16.0;

/// [fraction] 是拖动距离占宽度的比例，[velocity] 以宽度每秒计，向右为正。
bool dragBackPops({required double fraction, required double velocity}) =>
    fraction + velocity * _popLead >= _popReach;

double dragBackReleaseVelocity(double velocity) {
  final speed = velocity.abs();
  if (speed <= _flickSpeed) return velocity;
  final ramp = ((speed - _flickSpeed) / _flickSpeed).clamp(0.0, 1.0);
  return velocity * (1 + (_flickBoost - 1) * ramp);
}

/// go_router 用的页面。
final class AlistenPage<T> extends Page<T> {
  const AlistenPage({
    required this.child,
    this.task = false,
    this.push = false,
    this.returnTo,
    super.key,
    super.name,
    super.restorationId,
  }) : assert(!(task && push), 'a task page rises, it is never pushed');

  final Widget child;

  /// 从当前页面临时打开的任务，比如房间里的点歌。
  final bool task;

  /// 普通导航：从右边推入，不从被点的元素长出，比如设置和它下面的页面。不是
  /// 从 [ZoomSource] 里点开的页面也都普通推入。
  final bool push;

  /// 关闭时优先缩回的 [ZoomTarget]，比如房间收进迷你播放条。
  final String? returnTo;

  @override
  Route<T> createRoute(BuildContext context) {
    // 普通导航也要取走这次点按，免得之后的页面从它长出。
    final origin = TapOrigin.take();
    if (!task) {
      if (push) return PushPageRoute<T>._(this);
      final source = origin?.source;
      // 起点太小（头像、图标）时长出来只是角落里一个点飞满屏幕，也普通推入。
      if (origin != null &&
          source != null &&
          origin.rect.shortestSide >= AlistenSizes.largeTouchTarget) {
        final pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
        final image = source.snapshot(pixelRatio);
        return ZoomPageRoute<T>._(
          this,
          origin,
          image == null ? null : ZoomPicture(image, origin.shared),
        );
      }
      // 有返回目标的页面（房间）没有入口卡片时从右边滑入，关闭时照样收进
      // 返回目标。
      return returnTo == null
          ? PushPageRoute<T>._(this)
          : ZoomPageRoute<T>._(this, null);
    }
    final screen = MediaQuery.maybeSizeOf(context);
    final low =
        origin != null && screen != null && sitsLow(origin.rect, screen);
    return TaskPageRoute<T>._(this, low ? origin : null);
  }
}

/// 从刚点的元素长出、关闭时缩回去、可以用手指拖走的页面。
///
/// 路由进度表示页面出现的程度：底下页面压暗多少、遮罩多深、路由是否已完全
/// 盖住底下。拖动另用 [_pull] 记位移；松手关闭时记下当时的进度和外框，从那里
/// 缩回起点。
sealed class _ZoomRoute<T> extends PageRoute<T> {
  _ZoomRoute(AlistenPage<T> page, this._origin, [this._picture])
    : super(settings: page, fullscreenDialog: page.task);

  final LaunchOrigin? _origin;

  /// 起飞时入口卡片的样子，见 [ZoomSource]。
  final ZoomPicture? _picture;

  AlistenPage<T> get _page => settings as AlistenPage<T>;

  SpringDescription get _releaseSpring;

  SpringDescription get _openSpring => AlistenSprings.zoomOpen;
  SpringDescription get _closeSpring => AlistenSprings.zoomClose;

  /// 为 true 时页面用弹簧追手指，否则 1:1 跟手。
  bool get _trails;

  double _rubberExtent(double travel);
  bool _dismisses(double dragged, double velocity, double travel);

  /// 松手速度换算成每秒多少个拖动行程，向关闭方向为正。
  double _releaseSpeed(double velocity, double travel);

  /// 拖动 [pull] 后外框的位移和缩放；跟手的另一个方向见 [_cross]。
  (Offset, double) _dragGeometry(double pull, double travel);

  /// 没有起点、或要缩回的元素已不在屏幕上时，外框从哪长出、缩到哪去；[page]
  /// 是页面此刻的外框。为 null 时从底部升起。
  Rect? _fallback(Size screen, Rect page);

  /// 能否缩回 [rect] 处的元素。向下拖关闭的页面不缩回上方的元素。
  bool _returnsTo(Rect rect, Size screen) => true;

  BorderRadius _restRadius(BuildContext context);
  bool get _clipAtRest;

  final _pull = ValueNotifier<double>(0);
  _SpringDriver? _follower;

  // 横竖都跟手的页面，另一个方向（纵向）的位移。
  final _cross = ValueNotifier<double>(0);
  _SpringDriver? _crossFollower;
  double _crossDragged = 0;
  double? _shrinkFrom;
  (Offset, double)? _frozen;
  double? _nextVelocity;

  double _travel = 1;
  double _dragged = 0;
  bool _dragging = false;

  // 页面暂不可离开时不跟手，只累计距离，拖够了再询问页面。
  bool _held = false;

  // 被打开的任务页盖住时停掉动画：只露出遮罩下的一条，继续画是白白耗电。
  final _underTask = ValueNotifier<bool>(false);

  // 上面盖着普通导航推入的页面：被盖住时跟着向左移开，不只是原地压暗。
  final _underPush = ValueNotifier<bool>(false);

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    // 上面的页面关闭途中这里收到 null，那时还要跟着它移回来，不改。
    if (nextRoute is PushPageRoute) {
      _underPush.value = true;
    } else if (nextRoute is _ZoomRoute) {
      _underPush.value = false;
    }
  }

  bool _disposed = false;

  Widget _pausable(Widget child) => ValueListenableBuilder<bool>(
    valueListenable: _underTask,
    builder: (context, covered, child) =>
        TickerMode(enabled: !covered, child: child!),
    child: child,
  );

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  bool get _reduced {
    final context = navigator?.context;
    return context != null &&
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
  }

  @override
  Simulation? createSimulation({required bool forward}) {
    final target = forward ? 1.0 : 0.0;
    final velocity = _nextVelocity ?? 0;
    _nextVelocity = null;
    if (_reduced) return settledAt(target);
    return springTo(
      forward ? _openSpring : _closeSpring,
      from: controller!.value,
      to: target,
      velocity: velocity,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: _page.child,
    );
  }

  bool get _mayDrag =>
      isCurrent &&
      !isFirst &&
      !_dragging &&
      _shrinkFrom == null &&
      (animation!.isCompleted || _pull.value != 0) &&
      !navigator!.userGestureInProgress;

  void _dragStart(double travel) {
    _travel = travel;
    _dragged = 0;
    _held = popDisposition == RoutePopDisposition.doNotPop;
    if (_held) return;
    _dragging = true;
    navigator!.didStartUserGesture();
    _follower ??= _SpringDriver(
      navigator!,
      read: () => _pull.value,
      write: _setPull,
    );
    _follower!.stop();
    _crossFollower ??= _SpringDriver(
      navigator!,
      read: () => _cross.value,
      write: (value) => _cross.value = value,
    );
    _crossFollower!.stop();
    _crossDragged = _cross.value;
  }

  void _setPull(double value) {
    _pull.value = value;
    if (!_dragging && value == 0) {
      controller!.value = 1;
      navigator?.didStopUserGesture();
      return;
    }
    final away = (value / _travel).clamp(0.0, 1.0);
    controller!.value = math.min(1 - away, _almostShown);
  }

  /// [cross] 是另一个方向的移动，只有横竖都跟手的页面会报。
  void _dragUpdate(double delta, {double cross = 0}) {
    _dragged += delta;
    _crossDragged += cross;
    if (_held || !_dragging) return;
    _cross.value = _crossDragged;
    final target = _dragged < 0
        ? -rubberBand(-_dragged, _rubberExtent(_travel))
        : _dragged;
    if (_reduced || !_trails) {
      _follower!.stop();
      _setPull(target);
    } else {
      _follower!.chase(AlistenSprings.follow, target);
    }
  }

  void _dragEnd(double velocity) {
    final dismisses = _dismisses(_dragged, velocity, _travel);
    if (_held) {
      _held = false;
      if (dismisses) unawaited(navigator!.maybePop());
      return;
    }
    if (!_dragging) return;
    _dragging = false;
    _follower!.stop();
    if (dismisses) {
      _frozen = _dragGeometry(_pull.value, _travel);
      final shown = controller!.value;
      _shrinkFrom = shown;
      _nextVelocity = -_releaseSpeed(velocity, _travel) * shown;
      navigator!.pop();
      _stopGestureWhenSettled();
    } else {
      _putBack(_releaseSpeed(velocity, _travel) * _travel);
    }
  }

  void _dragCancel() {
    _held = false;
    if (!_dragging) return;
    _dragging = false;
    _follower!.stop();
    _putBack(0);
  }

  /// 把拖开的页面弹回原位；[velocity] 是像素每秒，向关闭方向为正。
  void _putBack(double velocity) {
    if (_reduced) {
      _cross.value = 0;
    } else if (_cross.value != 0) {
      _crossFollower?.chase(_releaseSpring, 0);
    }
    if (_reduced || _pull.value == 0) {
      _setPull(0);
      return;
    }
    _follower!.chase(_releaseSpring, 0, velocity: velocity);
  }

  void _stopGestureWhenSettled() {
    final navigator = this.navigator!;
    final controller = this.controller!;
    if (!controller.isAnimating) {
      navigator.didStopUserGesture();
      return;
    }
    late final AnimationStatusListener settled;
    settled = (status) {
      if (status.isAnimating) return;
      navigator.didStopUserGesture();
      controller.removeStatusListener(settled);
    };
    controller.addStatusListener(settled);
  }

  /// 外框此刻的起点：关闭时先找返回目标，再找起点元素现在的位置，都不在屏幕
  /// 上就用兜底。打开时元素若已不在树上，用点按时的位置。[element] 表示起点是
  /// 屏幕上的元素，[source] 表示它就是起飞时的入口卡片。
  ({Rect? rect, bool element, bool source}) _start(
    Size screen, {
    required bool closing,
    required Rect page,
  }) {
    final bounds = Offset.zero & screen;
    bool visible(Rect? rect) =>
        rect != null && rect.overlaps(bounds) && _returnsTo(rect, screen);
    if (closing) {
      final tag = _page.returnTo;
      final target = tag == null ? null : ZoomTarget.rectOf(tag);
      if (visible(target)) return (rect: target, element: true, source: false);
    }
    final origin = _origin;
    if (origin != null) {
      final now = origin.current;
      if (visible(now)) return (rect: now, element: true, source: true);
      if (!closing) return (rect: origin.rect, element: true, source: true);
    }
    return (rect: _fallback(screen, page), element: false, source: false);
  }

  double _growthOf(double shown) {
    final from = _shrinkFrom;
    if (from != null) return from <= 0 ? 0 : shown / from;
    if (_dragging || _pull.value != 0 || _cross.value != 0) return 1;
    return shown;
  }

  /// 外框和里面的页面。
  Widget _frame(
    BuildContext context,
    Animation<double> animation,
    Widget page, {
    required double travel,
  }) {
    final screen = MediaQuery.sizeOf(context);
    final restRadius = _restRadius(context);
    final surface = Theme.of(context).colorScheme.surface;
    return AnimatedBuilder(
      animation: Listenable.merge([animation, _pull, _cross]),
      child: page,
      builder: (context, page) {
        final closing =
            _shrinkFrom != null || animation.status == AnimationStatus.reverse;
        final growth = _growthOf(animation.value);
        final (offset, scale) = _frozen ?? _dragGeometry(_pull.value, travel);
        final start = _start(
          screen,
          closing: closing,
          page: Rect.fromCenter(
            center: screen.center(offset),
            width: screen.width * scale,
            height: screen.height * scale,
          ),
        );
        // 不回到入口卡片时（收进迷你播放条、卡片已不在屏幕上），卡片马上画
        // 出来，不留一个空位。
        if (closing && !start.source) _origin?.source?.show(this);
        _hideReturnTarget(
          away: closing || _dragging || _pull.value != 0 || _cross.value != 0,
          landing: closing && morphSolid(growth) < 1,
        );
        final picture = start.source ? _picture : null;
        final (double solid, double shown, double pictured) = switch (start) {
          // 从底部升起、滑进滑出时页面一直是实的。
          (element: false, rect: _, source: _) => (1, 1, 0),
          _ when picture == null => (
            morphSolid(growth),
            morphContent(growth, closing: closing),
            0,
          ),
          _ when closing => (
            1,
            ((growth - _contentGoneBy) / _contentSpan).clamp(0.0, 1.0),
            ((_pictureBackFrom - growth) / _pictureGoneBy).clamp(0.0, 1.0),
          ),
          _ => (
            1,
            ((growth - _contentFrom) / _contentSpan).clamp(0.0, 1.0),
            1 - (growth / _pictureGoneBy).clamp(0.0, 1.0),
          ),
        };
        return ZoomFrame(
          growth: growth,
          from: start.rect,
          riseBy: screen.height,
          fromRadius: start.element
              ? _origin?.radius ?? restRadius.topLeft.x
              : restRadius.topLeft.x,
          toRadius: restRadius,
          clipAtRest: _clipAtRest,
          fill: surface.withValues(alpha: surface.a * solid),
          offset: offset,
          scale: scale,
          picture: picture,
          pictured: pictured,
          // 打开途中内容还没显出来，读屏也要立刻读到新页面。
          child: Opacity(
            opacity: shown,
            alwaysIncludeSemantics: !closing,
            child: page,
          ),
        );
      },
    );
  }

  /// 页面就是返回目标（比如迷你播放条）展开的样子：拖动和缩回途中目标不画，
  /// 外框落到它上面、底色开始变透明时才画出来，画面上只有一份。
  void _hideReturnTarget({required bool away, required bool landing}) {
    final tag = _page.returnTo;
    if (tag == null) return;
    if (away && !landing) {
      ZoomTarget.hide(tag, this);
    } else {
      ZoomTarget.show(tag, this);
    }
  }

  @override
  void dispose() {
    final tag = _page.returnTo;
    if (tag != null) ZoomTarget.show(tag, this);
    _disposed = true;
    _follower?.dispose();
    _crossFollower?.dispose();
    _pull.dispose();
    _cross.dispose();
    _origin?.source?.show(this);
    _picture?.dispose();
    _underTask.dispose();
    _underPush.dispose();
    super.dispose();
  }
}

/// 从入口卡片长出的页面：外框从卡片长成全屏，卡片的快照随之淡去、页面淡入，
/// 底下的页面原地压暗；飞行期间卡片自己不画。关闭时缩回卡片现在的位置，卡片已
/// 不在屏幕上就向右滑出。页面任何位置向右拖动都能返回，拖动时横竖都跟手并
/// 缩小；页面里更深的横向手势（滚动、滑块、输入框）优先。
final class ZoomPageRoute<T> extends _ZoomRoute<T> {
  ZoomPageRoute._(super.page, super._origin, [super._picture]);

  @override
  void install() {
    super.install();
    _origin?.source?.hide(this);
    animation!.addStatusListener(_showSourceWhenClosed);
  }

  void _showSourceWhenClosed(AnimationStatus status) {
    if (status.isDismissed) _origin?.source?.show(this);
  }

  // 打开的第一帧页面在台下排版、不画，好让共享元素量出落点；卡片这一帧还得
  // 画着，否则屏幕上空一帧。
  @override
  set offstage(bool value) {
    super.offstage = value;
    final source = _origin?.source;
    if (source == null) return;
    if (value) {
      source.show(this);
    } else if (!animation!.isDismissed) {
      source.hide(this);
    }
  }

  @override
  Color? get barrierColor => null;

  // 转场由弹簧驱动，框架不用它计时；读它的地方按停稳时间算。
  @override
  Duration get transitionDuration => const Duration(milliseconds: 600);

  @override
  SpringDescription get _releaseSpring => AlistenSprings.release;

  @override
  bool get _trails => false;

  @override
  double _rubberExtent(double travel) => _pageRubberReach * travel;

  @override
  bool _dismisses(double dragged, double velocity, double travel) =>
      dragBackPops(fraction: dragged / travel, velocity: velocity / travel);

  @override
  double _releaseSpeed(double velocity, double travel) =>
      dragBackReleaseVelocity(velocity / travel);

  @override
  (Offset, double) _dragGeometry(double pull, double travel) {
    final moved = Offset(math.max(0, pull), _cross.value);
    final away = (moved.distance / travel).clamp(0.0, 1.0);
    return (Offset(pull, _cross.value), 1 - AlistenMotion.dragShrink * away);
  }

  @override
  Rect? _fallback(Size screen, Rect page) =>
      page.shift(Offset(screen.width, 0));

  @override
  BorderRadius _restRadius(BuildContext context) =>
      MediaQuery.maybeDisplayCornerRadiiOf(context) ?? BorderRadius.zero;

  @override
  bool get _clipAtRest => false;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _pageMotion;

  // 被任务页盖住时原地不动，由任务页的遮罩压暗。
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is ZoomPageRoute || nextRoute is PushPageRoute;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _DismissGesture(
      route: this,
      kind: _Dismiss.anyWayBack,
      child: _Covered(
        covered: secondaryAnimation,
        pushed: _underPush,
        child: _frame(
          context,
          animation,
          _pausable(child),
          travel: MediaQuery.sizeOf(context).width,
        ),
      ),
    );
  }
}

/// 普通导航：从右边推入，底下的页面略向左移并压暗；关闭时向右滑出。页面任何
/// 位置都能向右拖动返回，页面 1:1 跟手，页面里更深的横向手势优先。
final class PushPageRoute<T> extends _ZoomRoute<T> {
  PushPageRoute._(AlistenPage<T> page) : super(page, null);

  @override
  Color? get barrierColor => null;

  // 转场由弹簧驱动，框架不用它计时；读它的地方按停稳时间算。
  @override
  Duration get transitionDuration => const Duration(milliseconds: 600);

  // 推入和滑出都不冲过头：页面冲过左边会露出后面的页面。
  @override
  SpringDescription get _openSpring => AlistenSprings.page;

  @override
  SpringDescription get _closeSpring => AlistenSprings.page;

  @override
  SpringDescription get _releaseSpring => AlistenSprings.page;

  @override
  bool get _trails => false;

  @override
  double _rubberExtent(double travel) => _pageRubberReach * travel;

  @override
  bool _dismisses(double dragged, double velocity, double travel) =>
      dragBackPops(fraction: dragged / travel, velocity: velocity / travel);

  @override
  double _releaseSpeed(double velocity, double travel) =>
      dragBackReleaseVelocity(velocity / travel);

  @override
  (Offset, double) _dragGeometry(double pull, double travel) =>
      (Offset(math.max(0, pull), 0), 1);

  @override
  Rect? _fallback(Size screen, Rect page) => null;

  @override
  BorderRadius _restRadius(BuildContext context) => BorderRadius.zero;

  @override
  bool get _clipAtRest => false;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _pageMotion;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is ZoomPageRoute || nextRoute is PushPageRoute;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _DismissGesture(
      route: this,
      kind: _Dismiss.back,
      child: _Covered(
        covered: secondaryAnimation,
        pushed: _underPush,
        child: _slide(context, animation, _pausable(child)),
      ),
    );
  }

  // 拖动时路由进度就是没被拖开的那部分，页面的位置直接由进度给出：跟手、
  // 松手返回、按返回键关闭都是同一条路。
  Widget _slide(
    BuildContext context,
    Animation<double> animation,
    Widget page,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: animation,
      child: page,
      builder: (context, page) {
        final away = 1 - animation.value.clamp(0.0, 1.0);
        final width = MediaQuery.sizeOf(context).width;
        return Transform.translate(
          offset: Offset(width * away, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              boxShadow: [
                if (away > 0)
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: _pushShadowAlpha),
                    blurRadius: _pushShadowBlur,
                  ),
              ],
            ),
            child: page,
          ),
        );
      },
    );
  }
}

/// 任务页：从被点的元素长成顶部露出后面页面的卡片，没有起点时从底部升起；
/// 在没有纵向滚动的地方向下拖动就能关闭。底下的页面原地不动，由遮罩压暗。
final class TaskPageRoute<T> extends _ZoomRoute<T> {
  TaskPageRoute._(super.page, super._origin);

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor {
    final context = navigator?.context;
    return context == null ? null : AlistenColors.of(context).barrier;
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 600);

  @override
  SpringDescription get _releaseSpring => AlistenSprings.sheet;

  @override
  bool get _trails => false;

  @override
  double _rubberExtent(double travel) => _taskRubberExtent;

  @override
  bool _dismisses(double dragged, double velocity, double travel) =>
      sheetCloses(drag: dragged, velocity: velocity, height: travel);

  @override
  double _releaseSpeed(double velocity, double travel) => velocity / travel;

  @override
  (Offset, double) _dragGeometry(double pull, double travel) =>
      (Offset(0, pull), 1);

  @override
  Rect? _fallback(Size screen, Rect page) => null;

  @override
  bool _returnsTo(Rect rect, Size screen) => sitsLow(rect, screen);

  @override
  BorderRadius _restRadius(BuildContext context) =>
      const BorderRadius.vertical(top: _taskCorner);

  @override
  bool get _clipAtRest => true;

  _ZoomRoute<dynamic>? _below;

  @override
  void install() {
    super.install();
    animation!.addStatusListener(_coverBelow);
  }

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    _cover(false);
    _below = previousRoute is _ZoomRoute ? previousRoute : null;
    _cover(animation?.isCompleted ?? false);
    super.didChangePrevious(previousRoute);
  }

  void _coverBelow(AnimationStatus status) => _cover(status.isCompleted);

  void _cover(bool covered) {
    final below = _below;
    if (below == null || below._disposed) return;
    below._underTask.value = covered;
  }

  @override
  void dispose() {
    _cover(false);
    animation?.removeStatusListener(_coverBelow);
    super.dispose();
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final top = MediaQuery.paddingOf(context).top + _taskGap;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: _DismissGesture(
        route: this,
        kind: _Dismiss.down,
        child: _frame(
          context,
          animation,
          // 页面不再贴着屏幕顶部，状态栏的留白由路由让出。
          MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: _pausable(child),
          ),
          travel: MediaQuery.sizeOf(context).height - top,
        ),
      ),
    );
  }
}

// 所有页面共用：页面叠在页面上时，底下的页面用自己的转场压暗，不被包进上面
// 页面的转场，否则底页会换父节点、整页重建。
Widget? _pageMotion(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  bool allowSnapshotting,
  Widget? child,
) => null;

/// 被上面的页面盖住时压暗；盖上来的是普通导航推入的页面时还跟着向左移开。
final class _Covered extends StatelessWidget {
  const _Covered({
    required this.covered,
    required this.pushed,
    required this.child,
  });

  final Animation<double> covered;
  final ValueListenable<bool> pushed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([covered, pushed]),
      child: child,
      builder: (context, page) => Stack(
        fit: StackFit.expand,
        children: [
          Transform.translate(
            offset: Offset(
              pushed.value
                  ? -_pushParallax *
                        MediaQuery.sizeOf(context).width *
                        covered.value.clamp(0, 1)
                  : 0,
              0,
            ),
            child: page,
          ),
          if (covered.value > 0)
            IgnorePointer(
              child: ColoredBox(
                color: Color.from(
                  alpha: AlistenMotion.coveredDim * covered.value.clamp(0, 1),
                  red: 0,
                  green: 0,
                  blue: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _Dismiss {
  /// 向右拖，只跟横向。
  back,

  /// 向右拖起，之后横竖都跟。
  anyWayBack,

  /// 向下拖。
  down,
}

final class _DismissGesture extends StatefulWidget {
  const _DismissGesture({
    required this.route,
    required this.kind,
    required this.child,
  });

  final _ZoomRoute<dynamic> route;
  final _Dismiss kind;
  final Widget child;

  @override
  State<_DismissGesture> createState() => _DismissGestureState();
}

final class _DismissGestureState extends State<_DismissGesture> {
  late final DragGestureRecognizer _recognizer =
      switch (widget.kind) {
          _Dismiss.back => _DragBackRecognizer(debugOwner: this),
          _Dismiss.anyWayBack => _AnyWayBackRecognizer(debugOwner: this),
          _Dismiss.down => _DragDownRecognizer(debugOwner: this),
        }
        ..onStart = (_) {
          final size = (context.findRenderObject()! as RenderBox).size;
          widget.route._dragStart(
            widget.kind == _Dismiss.down ? size.height : size.width,
          );
        }
        ..onUpdate = (details) {
          widget.route._dragUpdate(
            details.primaryDelta ?? details.delta.dx,
            cross: widget.kind == _Dismiss.anyWayBack ? details.delta.dy : 0,
          );
        }
        ..onEnd = (details) {
          widget.route._dragEnd(
            details.primaryVelocity ?? details.velocity.pixelsPerSecond.dx,
          );
        }
        ..onCancel = () {
          widget.route._dragCancel();
        };

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (widget.route._mayDrag) _recognizer.addPointer(event);
      },
      child: widget.child,
    );
  }
}

/// 只认向右越过 30 的拖动。页面里更深的横向手势先加入竞争，先越过它们自己的
/// 阈值就会胜出。
final class _DragBackRecognizer extends HorizontalDragGestureRecognizer {
  _DragBackRecognizer({super.debugOwner}) {
    // 单独在竞争里时默认会胜出，按下就开始拖动。
    onlyAcceptDragOnThreshold = true;
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved > _dragBackSlop;
}

/// 和 [_DragBackRecognizer] 一样只认向右越过 30、且横向多于纵向的拖动；认下
/// 之后横竖两个方向都报。
final class _AnyWayBackRecognizer extends PanGestureRecognizer {
  _AnyWayBackRecognizer({super.debugOwner}) {
    onlyAcceptDragOnThreshold = true;
  }

  Offset _moved = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _moved = Offset.zero;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _moved += event.delta;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => _moved.dx > _dragBackSlop && _moved.dx > _moved.dy.abs();
}

/// 只认向下的拖动。页面里的纵向滚动更深，在它上面拖动只滚动内容。
final class _DragDownRecognizer extends VerticalDragGestureRecognizer {
  _DragDownRecognizer({super.debugOwner}) {
    onlyAcceptDragOnThreshold = true;
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved > computeHitSlop(pointerDeviceKind, gestureSettings);
}

/// 用弹簧追一个会变的目标，逐帧写入数值。
final class _SpringDriver {
  _SpringDriver(
    TickerProvider vsync, {
    required this.read,
    required this.write,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  final double Function() read;
  final void Function(double value) write;
  late final Ticker _ticker;
  Simulation? _simulation;
  double _velocity = 0;

  /// 时钟走到的地方，和当前这段模拟从时钟的哪一刻算起。
  Duration _now = Duration.zero;
  Duration _origin = Duration.zero;

  /// 换目标时不重启时钟：手指每帧至少报一次移动，重启后每帧都从零算起，
  /// 写回的总是原值，页面就停着不动。新的一段从上一帧写下的位置和速度接着走。
  void chase(SpringDescription spring, double target, {double? velocity}) {
    _simulation = springTo(
      spring,
      from: read(),
      to: target,
      velocity: velocity ?? _velocity,
    );
    if (_ticker.isActive) {
      _origin = _now;
    } else {
      _now = Duration.zero;
      _origin = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    _now = elapsed;
    final simulation = _simulation;
    if (simulation == null) return;
    final time =
        (elapsed - _origin).inMicroseconds / Duration.microsecondsPerSecond;
    final done = simulation.isDone(time);
    final value = simulation.x(time);
    _velocity = simulation.dx(time);
    if (done) stop();
    write(value);
  }

  void stop() {
    _ticker.stop();
    _simulation = null;
    _velocity = 0;
  }

  void dispose() => _ticker.dispose();
}
