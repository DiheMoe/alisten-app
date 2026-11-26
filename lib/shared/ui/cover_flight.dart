import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:alisten/shared/theme/motion.dart';
import 'package:flutter/widgets.dart';

// 等落点出现最多等这么多帧，等不到就落在区域的边上。
const _waitFrames = 20;

// 途中略微抬起，落下时回到原大。
const _lift = 0.12;

// 落点看不见时，飞到区域边上缩成这么大，后一半路程里淡去。
const _missedScale = 0.6;
const _fadeFrom = 0.5;

/// 标出一处可以起飞、接住或圈住飞行元素的地方，按 [tag] 查找，见 [fly]。
class FlightMark extends StatefulWidget {
  const FlightMark({required this.tag, required this.child, super.key});

  final Object tag;
  final Widget child;

  static final _marks = <Object, Set<_FlightMarkState>>{};

  // 飞向这些标记的元素还没到：标记处先空着，画面上只有一份。
  static final _awaited = <Object, int>{};

  /// 把 [from] 处的样子复制一份飞到 [to] 处，比如点的歌的封面飞进队列。[to] 还
  /// 没出现时等它几帧；它在 [area] 里看不见（队列很长，新的一首在下面）时，
  /// 落在 [area] 靠它那一边的边上并淡去。[from] 或 [area] 不在屏幕上、或系统
  /// 要求减少动态效果时不飞。
  static void fly({
    required Object from,
    required Object to,
    required Object area,
  }) {
    final source = _seen(from);
    final start = source?._visible;
    if (source == null || start == null || _seen(area) == null) return;
    final context = source.context;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Flight(
        start: start,
        look: InheritedTheme.captureAll(context, source.widget.child),
        to: to,
        area: area,
        onLanded: () => entry
          ..remove()
          ..dispose(),
      ),
    );
    _hold(to);
    overlay.insert(entry);
  }

  static _FlightMarkState? _seen(Object tag) {
    for (final state in _marks[tag] ?? const <_FlightMarkState>{}) {
      if (state._visible != null) return state;
    }
    return null;
  }

  static Rect? _rectOf(Object tag) {
    for (final state in _marks[tag] ?? const <_FlightMarkState>{}) {
      if (state._rect case final rect?) return rect;
    }
    return null;
  }

  static void _hold(Object tag) {
    _awaited[tag] = (_awaited[tag] ?? 0) + 1;
    _refresh(tag);
  }

  static void _release(Object tag) {
    final left = (_awaited[tag] ?? 1) - 1;
    if (left > 0) {
      _awaited[tag] = left;
      return;
    }
    _awaited.remove(tag);
    _refresh(tag);
  }

  static void _refresh(Object tag) {
    for (final state in _marks[tag] ?? const <_FlightMarkState>{}) {
      state._changed();
    }
  }

  @override
  State<FlightMark> createState() => _FlightMarkState();
}

class _FlightMarkState extends State<FlightMark> {
  @override
  void initState() {
    super.initState();
    _register(widget.tag);
  }

  @override
  void didUpdateWidget(FlightMark oldWidget) {
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

  void _register(Object tag) => (FlightMark._marks[tag] ??= {}).add(this);

  void _forget(Object tag) {
    final states = FlightMark._marks[tag];
    if (states == null) return;
    states.remove(this);
    if (states.isEmpty) FlightMark._marks.remove(tag);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Rect? get _rect {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  // 祖先们裁过之后还看得见的部分；一点都看不见（比如面板收起了）时为 null。
  Rect? get _visible {
    var seen = _rect;
    if (seen == null) return null;
    var child = context.findRenderObject()!;
    for (var parent = child.parent; parent != null; parent = child.parent) {
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        seen = seen!.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
        if (seen.isEmpty) return null;
      }
      child = parent;
    }
    return seen;
  }

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: FlightMark._awaited.containsKey(widget.tag) ? 0 : 1,
    child: widget.child,
  );
}

class _Flight extends StatefulWidget {
  const _Flight({
    required this.start,
    required this.look,
    required this.to,
    required this.area,
    required this.onLanded,
  });

  final Rect start;
  final Widget look;
  final Object to;
  final Object area;
  final VoidCallback onLanded;

  @override
  State<_Flight> createState() => _FlightState();
}

class _FlightState extends State<_Flight> with SingleTickerProviderStateMixin {
  late final AnimationController _progress =
      AnimationController.unbounded(vsync: this)..addStatusListener((status) {
        if (status.isCompleted) _land();
      });
  int _waited = 0;
  bool _landed = false;
  Rect? _last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_aim);
  }

  void _aim(Duration _) {
    if (!mounted) return;
    if (FlightMark._rectOf(widget.to) != null || ++_waited > _waitFrames) {
      _progress.animateWith(
        springTo(AlistenSprings.coverFlight, from: 0, to: 1),
      );
      return;
    }
    WidgetsBinding.instance
      ..addPostFrameCallback(_aim)
      ..scheduleFrame();
  }

  void _land() {
    if (_landed) return;
    _landed = true;
    FlightMark._release(widget.to);
    widget.onLanded();
  }

  @override
  void dispose() {
    if (!_landed) FlightMark._release(widget.to);
    _progress.dispose();
    super.dispose();
  }

  // 每帧重新量：队列在滚动、新的一行还在排进来时也追得上。
  ({Rect rect, double shown}) _landing() {
    final area = FlightMark._seen(widget.area)?._visible;
    final target = FlightMark._rectOf(widget.to);
    if (area == null) return (rect: _last ?? widget.start, shown: 0);
    if (target != null && area.contains(target.center)) {
      return (rect: target, shown: 1);
    }
    final size = widget.start.size * _missedScale;
    final below = target == null || target.center.dy > area.center.dy;
    return (
      rect: Rect.fromCenter(
        center: Offset(
          target?.center.dx ?? area.center.dx,
          below ? area.bottom - size.height / 2 : area.top + size.height / 2,
        ),
        width: size.width,
        height: size.height,
      ),
      shown: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      child: widget.look,
      builder: (context, look) {
        final travelled = _progress.value;
        final landing = _landing();
        _last = landing.rect;
        final fading = ((travelled - _fadeFrom) / (1 - _fadeFrom)).clamp(
          0.0,
          1.0,
        );
        return Positioned.fromRect(
          rect: Rect.lerp(widget.start, landing.rect, travelled)!,
          child: IgnorePointer(
            child: Opacity(
              opacity: lerpDouble(1, landing.shown, fading)!,
              child: Transform.scale(
                scale:
                    1 + _lift * math.sin(math.pi * travelled.clamp(0.0, 1.0)),
                child: FittedBox(fit: BoxFit.fill, child: look),
              ),
            ),
          ),
        );
      },
    );
  }
}
