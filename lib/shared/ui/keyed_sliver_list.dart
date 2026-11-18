import 'package:alisten/shared/theme/motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 按键比较前后两次的 [items]，把变化做成动画：
///
/// - 留下的行顺序不变时，新加的行展开淡入，删掉的行收起淡出，其余的行随之移动。
/// - 留下的行换了顺序时，每行从原来的位置滑到新位置；新加的行原地淡入，删掉
///   的行直接消失，免得一行同时被展开和滑动推着走。
///
/// 一次超过 [AlistenMotion.listMaxAnimatedChanges] 处变化，或者系统要求减少动态
/// 效果时，直接换成新列表。
final class KeyedSliverList<T> extends StatefulWidget {
  const KeyedSliverList({
    required this.items,
    required this.keyOf,
    required this.itemBuilder,
    this.addRepaintBoundaries = true,
    super.key,
  });

  final List<T> items;
  final Object Function(T item) keyOf;

  /// [index] 是这一行在 [items] 里的位置；正在离开的行是它离开前的位置。
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final bool addRepaintBoundaries;

  @override
  State<KeyedSliverList<T>> createState() => _KeyedSliverListState<T>();
}

enum _Change { none, enter, leave }

final class _Row<T> {
  _Row(this.key, this.item, this.index, this.change);

  final Object key;
  final T item;
  final int index;
  final _Change change;

  /// 换顺序时这一行上次画在列表内容里的纵向位置，从那里滑过来。
  double? origin;
}

final class _KeyedSliverListState<T> extends State<KeyedSliverList<T>>
    with SingleTickerProviderStateMixin {
  late final _motion =
      AnimationController(
        vsync: this,
        duration: AlistenMotion.listChange,
        value: 1,
      )..addStatusListener((status) {
        if (status.isCompleted) setState(_settle);
      });
  late final _entering = CurvedAnimation(
    parent: _motion,
    curve: AlistenMotion.listIn,
  );
  late final _leaving = ReverseAnimation(
    CurvedAnimation(parent: _motion, curve: AlistenMotion.listOut),
  );

  // 每一行最近一次画在列表内容里的纵向位置，换顺序时作为滑动的起点。
  final _positions = <Object, double>{};
  late List<_Row<T>> _rows = _still(widget.items);
  bool _reordering = false;

  List<_Row<T>> _still(List<T> items) => [
    for (final (index, item) in items.indexed)
      _Row(widget.keyOf(item), item, index, _Change.none),
  ];

  void _settle() {
    _rows = [
      for (final row in _rows)
        if (row.change != _Change.leave)
          _Row(row.key, row.item, row.index, _Change.none),
    ];
    _reordering = false;
  }

  @override
  void didUpdateWidget(KeyedSliverList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_motion.isAnimating) _settle();
    final before = _rows;
    final newKeys = [for (final item in widget.items) widget.keyOf(item)];
    final newSet = newKeys.toSet();
    final oldKeys = [for (final row in before) row.key];
    final oldSet = oldKeys.toSet();
    final kept = [
      for (final key in oldKeys)
        if (newSet.contains(key)) key,
    ];
    final keptAfter = [
      for (final key in newKeys)
        if (oldSet.contains(key)) key,
    ];
    final reordering = !listEquals(kept, keptAfter);
    var changes = before.length - kept.length + newKeys.length - kept.length;
    if (reordering) {
      for (var i = 0; i < kept.length; i++) {
        if (kept[i] != keptAfter[i]) changes++;
      }
    }
    if (changes == 0) {
      _rows = _still(widget.items);
      return;
    }
    if (changes > AlistenMotion.listMaxAnimatedChanges ||
        reducedMotion(context)) {
      _rows = _still(widget.items);
      _motion.value = 1;
      return;
    }
    _reordering = reordering;
    _rows = reordering ? _reordered(oldSet) : _merged(before, newSet, oldSet);
    _motion.forward(from: 0);
  }

  // 顺序变了：留下的行带上原来的位置，新加的行原地淡入。
  List<_Row<T>> _reordered(Set<Object> oldSet) {
    return [
      for (final (index, item) in widget.items.indexed)
        if (oldSet.contains(widget.keyOf(item)))
          _Row(widget.keyOf(item), item, index, _Change.none)
            ..origin = _positions[widget.keyOf(item)]
        else
          _Row(widget.keyOf(item), item, index, _Change.enter),
    ];
  }

  // 顺序没变：删掉的行留在原处收起，新加的行插在新位置展开。
  List<_Row<T>> _merged(
    List<_Row<T>> before,
    Set<Object> newSet,
    Set<Object> oldSet,
  ) {
    final rows = <_Row<T>>[];
    var old = 0;
    for (final (index, item) in widget.items.indexed) {
      final key = widget.keyOf(item);
      if (oldSet.contains(key)) {
        while (old < before.length && before[old].key != key) {
          final gone = before[old++];
          rows.add(_Row(gone.key, gone.item, gone.index, _Change.leave));
        }
        old++;
        rows.add(_Row(key, item, index, _Change.none));
      } else {
        rows.add(_Row(key, item, index, _Change.enter));
      }
    }
    for (; old < before.length; old++) {
      final gone = before[old];
      if (!newSet.contains(gone.key)) {
        rows.add(_Row(gone.key, gone.item, gone.index, _Change.leave));
      }
    }
    return rows;
  }

  @override
  void dispose() {
    _entering.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final indexOf = {for (final (index, row) in _rows.indexed) row.key: index};
    final scroll = Scrollable.maybeOf(context)?.position;
    return SliverList.builder(
      itemCount: _rows.length,
      addRepaintBoundaries: widget.addRepaintBoundaries,
      findChildIndexCallback: (key) =>
          key is ValueKey<Object> ? indexOf[key.value] : null,
      itemBuilder: (context, index) {
        final row = _rows[index];
        final leaving = row.change == _Change.leave;
        final Animation<double> size;
        final Animation<double> opacity;
        switch (row.change) {
          case _Change.enter:
            size = _reordering ? kAlwaysCompleteAnimation : _entering;
            opacity = _entering;
          case _Change.leave:
            size = _leaving;
            opacity = _leaving;
          case _Change.none:
            size = kAlwaysCompleteAnimation;
            opacity = kAlwaysCompleteAnimation;
        }
        return KeyedSubtree(
          key: ValueKey<Object>(row.key),
          child: _Tracked(
            rowKey: row.key,
            positions: _positions,
            origin: row.origin,
            progress: _entering,
            opacity: opacity,
            scroll: scroll,
            child: IgnorePointer(
              ignoring: leaving,
              child: ExcludeSemantics(
                excluding: leaving,
                child: SizeTransition(
                  sizeFactor: size,
                  alignment: Alignment.topCenter,
                  child: widget.itemBuilder(context, row.item, row.index),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 绘制时记下自己在列表内容里的位置；有 [origin] 时从那里按 [progress] 滑到
/// 现在的位置，并按 [opacity] 淡入淡出。
///
/// 淡入淡出直接在绘制时叠透明度，不用 Opacity 或 FadeTransition：它们半透明时
/// 是重绘边界，行里的 EdgeFadeItem 滚动时就不会随视口重绘。
final class _Tracked extends SingleChildRenderObjectWidget {
  const _Tracked({
    required this.rowKey,
    required this.positions,
    required this.origin,
    required this.progress,
    required this.opacity,
    required this.scroll,
    super.child,
  });

  final Object rowKey;
  final Map<Object, double> positions;
  final double? origin;
  final Animation<double> progress;
  final Animation<double> opacity;
  final ScrollPosition? scroll;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTracked(
    rowKey: rowKey,
    positions: positions,
    scroll: scroll,
    origin: origin,
    progress: progress,
    opacity: opacity,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderTracked renderObject) {
    renderObject
      ..rowKey = rowKey
      ..positions = positions
      ..origin = origin
      ..progress = progress
      ..opacity = opacity
      ..scroll = scroll;
  }
}

final class _RenderTracked extends RenderProxyBox {
  _RenderTracked({
    required this.rowKey,
    required this.positions,
    required this.scroll,
    required this._origin,
    required this._progress,
    required this._opacity,
  });

  Object rowKey;
  Map<Object, double> positions;
  ScrollPosition? scroll;

  double? _origin;
  set origin(double? value) {
    if (value == _origin) return;
    _origin = value;
    markNeedsPaint();
  }

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (identical(value, _progress)) return;
    if (attached) {
      _progress.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _progress = value;
    markNeedsPaint();
  }

  Animation<double> _opacity;
  set opacity(Animation<double> value) {
    if (identical(value, _opacity)) return;
    if (attached) {
      _opacity.removeListener(_opacityChanged);
      value.addListener(_opacityChanged);
    }
    _opacity = value;
    _opacityChanged();
  }

  bool _translucent = false;

  void _opacityChanged() {
    final translucent = _opacity.value < 1;
    if (translucent != _translucent) {
      _translucent = translucent;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _opacity.value < 1;

  // 不滑动时在列表内容里的纵向位置。
  double get _here => localToGlobal(Offset.zero).dy + (scroll?.pixels ?? 0);

  double get _slide {
    final origin = _origin;
    if (origin == null || _progress.value >= 1) return 0;
    return (origin - _here) * (1 - _progress.value);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsPaint);
    _opacity.addListener(_opacityChanged);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsPaint);
    _opacity.removeListener(_opacityChanged);
    super.detach();
  }

  // 滑动途中的位置也用于坐标换算和点按判定，看到哪里就点到哪里。
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, _slide, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintOffset(
      offset: Offset(0, _slide),
      position: position,
      hitTest: (result, position) =>
          super.hitTestChildren(result, position: position),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final here = _here;
    final slide = _slide;
    positions[rowKey] = here + slide;
    final alpha = Color.getAlphaFromOpacity(_opacity.value.clamp(0, 1));
    if (alpha == 0) {
      layer = null;
      return;
    }
    void slid(PaintingContext context, Offset offset) {
      if (slide == 0) {
        super.paint(context, offset);
        return;
      }
      context.pushTransform(
        needsCompositing,
        offset,
        Matrix4.translationValues(0, slide, 0),
        super.paint,
      );
    }

    if (alpha == 255) {
      layer = null;
      slid(context, offset);
      return;
    }
    layer = context.pushOpacity(
      offset,
      alpha,
      slid,
      oldLayer: layer as OpacityLayer?,
    );
  }
}
