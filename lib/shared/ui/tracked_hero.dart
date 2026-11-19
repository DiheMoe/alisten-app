import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 在会缩放、移动的页面之间飞的 [Hero]，比如从入口卡片长出的页面里的封面。
///
/// [Hero] 按页面停稳之后的位置飞，进度还套着先快后慢的曲线：页面还在长大或
/// 缩回，飞行的元素就先到了，和页面脱开。这里两头都按此刻真正画在屏幕上的位置
/// 算，进度就是页面转场的进度，飞行的元素一直贴着正在长大或缩回的页面，和页面
/// 同时停稳。两头都要用它。路径是直线。
class TrackedHero extends StatefulWidget {
  const TrackedHero({
    required this.tag,
    required this.child,
    this.flightShuttleBuilder,
    super.key,
  });

  final Object tag;
  final HeroFlightShuttleBuilder? flightShuttleBuilder;
  final Widget child;

  @override
  State<TrackedHero> createState() => _TrackedHeroState();
}

final _mounted = <Object, Set<_TrackedHeroState>>{};

class _TrackedHeroState extends State<TrackedHero> {
  @override
  void initState() {
    super.initState();
    _register(widget.tag);
  }

  @override
  void didUpdateWidget(TrackedHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tag == widget.tag) return;
    _forget(oldWidget.tag);
    _register(widget.tag);
  }

  @override
  void dispose() {
    _forget(widget.tag);
    super.dispose();
  }

  void _register(Object tag) => (_mounted[tag] ??= {}).add(this);

  void _forget(Object tag) {
    final states = _mounted[tag];
    if (states == null) return;
    states.remove(this);
    if (states.isEmpty) _mounted.remove(tag);
  }

  RenderBox? get _box {
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  // 与 [Hero] 量起止点的方法相同：相对页面本身，不计页面转场的缩放和位移。
  Rect? get _resting {
    final box = _box;
    final page = ModalRoute.of(context)?.subtreeContext?.findRenderObject();
    if (box == null || page is! RenderBox || !page.attached) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(page),
      Offset.zero & box.size,
    );
  }

  // 此刻画在导航器里的位置，算上页面转场。页面刚从卡片长出时大半还被外框
  // 裁着，元素可能在看不见的地方；这时把它挪进外框里看得见的部分，放不下就等
  // 比缩小，飞行的元素才不会飞出页面。
  Rect? get _live {
    final box = _box;
    final overlay = Navigator.maybeOf(context)?.overlay?.context
        .findRenderObject();
    if (box == null || overlay is! RenderBox || !overlay.attached) return null;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(overlay),
      Offset.zero & box.size,
    );
    final visible = _visibleIn(box, overlay);
    return visible == null || visible.isEmpty ? rect : _fit(rect, visible);
  }

  // 祖先们画 [box] 时裁出的范围，在 [ancestor] 的坐标里。
  static Rect? _visibleIn(RenderObject box, RenderObject ancestor) {
    Rect? visible;
    RenderObject child = box;
    while (child != ancestor) {
      final parent = child.parent;
      if (parent == null) return visible;
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        final seen = MatrixUtils.transformRect(
          parent.getTransformTo(ancestor),
          clip,
        );
        visible = visible?.intersect(seen) ?? seen;
      }
      child = parent;
    }
    return visible;
  }

  static Rect _fit(Rect rect, Rect within) {
    final scale = math.min(
      1.0,
      math.min(within.width / rect.width, within.height / rect.height),
    );
    final fitted = Rect.fromCenter(
      center: rect.center,
      width: rect.width * scale,
      height: rect.height * scale,
    );
    double into(double low, double high, double min, double max) =>
        low < min ? min - low : (high > max ? max - high : 0);
    return fitted.shift(
      Offset(
        into(fitted.left, fitted.right, within.left, within.right),
        into(fitted.top, fitted.bottom, within.top, within.bottom),
      ),
    );
  }

  Tween<Rect?> _tween(Rect? begin, Rect? end) {
    _TrackedHeroState? at(Rect? resting) {
      if (resting == null) return null;
      for (final state in _mounted[widget.tag] ?? const <_TrackedHeroState>{}) {
        final rect = state._resting;
        if (rect != null &&
            (rect.topLeft - resting.topLeft).distance < 0.5 &&
            (rect.width - resting.width).abs() < 0.5 &&
            (rect.height - resting.height).abs() < 0.5) {
          return state;
        }
      }
      return null;
    }

    return _flight = _TrackingRectTween(
      begin: begin,
      end: end,
      from: at(begin),
      to: at(end),
    );
  }

  // 飞行用的是终点那头的 tween 和飞行元素，见 [Hero]。
  _TrackingRectTween? _flight;

  // 终点这头总要给 [Hero] 一个飞行元素（好包上 [_CatchUp]），自己没有样式时
  // 照 [Hero] 的规矩借起点那头的。
  Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final look = widget.flightShuttleBuilder ?? _ownLookOf(fromHeroContext);
    return _CatchUp(
      hero: this,
      child:
          look?.call(
            flightContext,
            animation,
            direction,
            fromHeroContext,
            toHeroContext,
          ) ??
          (toHeroContext.widget as Hero).child,
    );
  }

  static HeroFlightShuttleBuilder? _ownLookOf(BuildContext heroContext) {
    final hero = heroContext.widget as Hero;
    final tracked = heroContext.findAncestorStateOfType<_TrackedHeroState>();
    return tracked != null && hero.flightShuttleBuilder == tracked._shuttle
        ? tracked.widget.flightShuttleBuilder
        : hero.flightShuttleBuilder;
  }

  @override
  Widget build(BuildContext context) => Hero(
    tag: widget.tag,
    curve: Curves.linear,
    createRectTween: _tween,
    flightShuttleBuilder: _shuttle,
    child: widget.child,
  );
}

/// [Hero] 在构建阶段摆放飞行的元素，那时页面这一帧的缩放和位移还没更新，量到
/// 的是上一帧的位置；刚从台下回来的第一帧量到的更是页面停稳后的样子。绘制时
/// 两头的位置都已是这一帧的，这里按它们重算，把飞行的元素挪过去。
class _CatchUp extends SingleChildRenderObjectWidget {
  const _CatchUp({required this.hero, required super.child});

  final _TrackedHeroState hero;

  @override
  _RenderCatchUp createRenderObject(BuildContext context) =>
      _RenderCatchUp(hero, Overlay.of(context));

  @override
  void updateRenderObject(BuildContext context, _RenderCatchUp renderObject) {
    renderObject
      ..hero = hero
      ..overlay = Overlay.of(context);
  }
}

class _RenderCatchUp extends RenderProxyBox {
  _RenderCatchUp(this.hero, this.overlay);

  _TrackedHeroState hero;
  OverlayState overlay;

  Matrix4? get _catchUp {
    final flight = hero._flight;
    final planned = flight?._planned;
    final theater = overlay.context.findRenderObject();
    if (flight == null ||
        planned == null ||
        !hasSize ||
        size.isEmpty ||
        theater is! RenderBox ||
        !theater.attached) {
      return null;
    }
    final laid = MatrixUtils.transformRect(
      getTransformTo(theater),
      Offset.zero & size,
    );
    // 摆放它的不是这个 tween 算出的位置时（比如飞行中途被转向），不去动它。
    if ((laid.topLeft - planned.topLeft).distance > 0.5 ||
        (laid.width - planned.width).abs() > 0.5 ||
        (laid.height - planned.height).abs() > 0.5) {
      return null;
    }
    final now = flight._now;
    if (now == null) return null;
    return Matrix4.translationValues(
      now.left - laid.left,
      now.top - laid.top,
      0,
    )..scaleByDouble(now.width / laid.width, now.height / laid.height, 1, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final catchUp = _catchUp;
    if (catchUp == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      catchUp,
      super.paint,
      oldLayer: layer is TransformLayer ? layer! as TransformLayer : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final catchUp = _catchUp;
    if (catchUp != null) transform.multiply(catchUp);
  }
}

final class _TrackingRectTween extends RectTween {
  _TrackingRectTween({
    required super.begin,
    required super.end,
    required this.from,
    required this.to,
  });

  final _TrackedHeroState? from;
  final _TrackedHeroState? to;

  double? _t;
  Rect? _planned;

  Rect? _at(double t) {
    final begin = (from?.mounted ?? false) ? from!._live : null;
    final end = (to?.mounted ?? false) ? to!._live : null;
    return Rect.lerp(begin ?? this.begin, end ?? this.end, t);
  }

  Rect? get _now {
    final t = _t;
    return t == null ? null : _at(t);
  }

  // 两端也按此刻的位置算，不用停稳时的。
  @override
  Rect? transform(double t) => lerp(t);

  @override
  Rect? lerp(double t) {
    _t = t;
    return _planned = _at(t);
  }
}
