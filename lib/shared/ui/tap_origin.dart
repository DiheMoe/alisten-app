import 'dart:ui' as ui show Image;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 一次点按：被点的元素在屏幕上的位置和圆角，是接下来打开的页面或面板的起点。
final class LaunchOrigin {
  LaunchOrigin._(
    RenderBox box, {
    required this.radius,
    this.source,
    this.shared = const [],
  }) : rect = _globalRect(box),
       _box = WeakReference(box);

  /// 不跟随任何元素的起点。
  LaunchOrigin.at(
    this.rect, {
    this.radius = 0,
    this.source,
    this.shared = const [],
  }) : _box = null;

  /// 点按时的位置。
  final Rect rect;
  final double radius;

  /// 被点的是入口卡片时是它；页面只从入口卡片长出，否则普通推入。
  final ZoomSourceHandle? source;

  /// 入口卡片里会自己飞过去的共享元素（[Hero]）的位置，按卡片宽高的比例，
  /// 见 [ZoomPicture.holes]。
  final List<Rect> shared;
  final WeakReference<RenderBox>? _box;

  /// 元素现在的位置；元素已不在树上时为 null。
  Rect? get current {
    final box = _box;
    if (box == null) return rect;
    final target = box.target;
    if (target == null || !target.attached || !target.hasSize) return null;
    return _globalRect(target);
  }
}

Rect _globalRect(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

/// 从下往上出现、向下拖动关闭的界面（底部面板、点歌页）只从屏幕下半部分的
/// 元素长出：元素在上方时，长出是向下的，和向下拖的关闭手势方向相反。
bool sitsLow(Rect rect, Size screen) => rect.center.dy > screen.height / 2;

/// 记住最近一次点按。路由创建时取走，一次点按只当一次起点；1 秒后失效，等网络
/// 返回之后才打开的页面就不再从它长出。
abstract final class TapOrigin {
  static const lifetime = Duration(seconds: 1);

  // 不用计时器清除：测试结束时还挂着的计时器会让测试失败。
  static final _clock = Stopwatch()..start();

  @visibleForTesting
  static Duration Function() now = _elapsed;

  static Duration _elapsed() => _clock.elapsed;

  static LaunchOrigin? _last;
  static Duration _at = Duration.zero;

  /// 点在入口卡片里时，起点是整张卡片。
  static void record(BuildContext context, {double radius = 0}) {
    final source = context.findAncestorStateOfType<_ZoomSourceState>();
    final box = (source?.context ?? context).findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    _last = LaunchOrigin._(
      box,
      radius: radius,
      source: source,
      shared: source?._sharedParts() ?? const [],
    );
    _at = now();
  }

  static LaunchOrigin? take() {
    final origin = _last;
    _last = null;
    if (origin == null || now() - _at > lifetime) return null;
    return origin.current == null ? null : origin;
  }

  @visibleForTesting
  static void reset() {
    _last = null;
    now = _elapsed;
  }
}

/// 页面关闭时优先缩回的元素，按 [tag] 查找，比如房间收进迷你播放条。
class ZoomTarget extends StatefulWidget {
  const ZoomTarget({required this.tag, required this.child, super.key});

  final String tag;
  final Widget child;

  static final _targets = <String, _ZoomTargetState>{};

  /// 元素现在的全局位置；不在树上或还没布局时为 null。
  static Rect? rectOf(String tag) {
    final box = _targets[tag]?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return _globalRect(box);
  }

  /// 同 [ZoomSourceHandle.hide]：都放开才重新画出来。
  static void hide(String tag, Object by) => _targets[tag]?._hide(by);
  static void show(String tag, Object by) => _targets[tag]?._show(by);

  @override
  State<ZoomTarget> createState() => _ZoomTargetState();
}

class _ZoomTargetState extends State<ZoomTarget> {
  final _hiding = GlobalKey();
  final _hiders = <Object>{};

  // 页面在构建阶段调用，这里只标记重绘，不重建。
  void _hide(Object by) {
    if (_hiders.add(by)) _sync();
  }

  void _show(Object by) {
    if (_hiders.remove(by)) _sync();
  }

  void _sync() {
    final hiding = _hiding.currentContext?.findRenderObject();
    if (hiding is _RenderHiding) hiding.hidden = _hiders.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    ZoomTarget._targets[widget.tag] = this;
  }

  @override
  void didUpdateWidget(ZoomTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tag == widget.tag) return;
    _forget(oldWidget.tag);
    ZoomTarget._targets[widget.tag] = this;
  }

  void _forget(String tag) {
    if (ZoomTarget._targets[tag] == this) ZoomTarget._targets.remove(tag);
  }

  @override
  void dispose() {
    _forget(widget.tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _Hiding(key: _hiding, hidden: _hiders.isNotEmpty, child: widget.child);
}

/// 能长出页面的入口：被点的东西就是要打开的东西，比如房间卡片、歌单卡片。只有
/// 从它里面点开的页面才从它长出，其余页面普通推入。
///
/// 页面起飞时拍下它的样子画在外框里，飞行期间它自己不画，画面上只有一份。
class ZoomSource extends StatefulWidget {
  const ZoomSource({required this.child, super.key});

  final Widget child;

  @override
  State<ZoomSource> createState() => _ZoomSourceState();
}

/// 入口卡片起飞时的样子。卡片里的共享元素（[Hero]，比如封面）自己飞过去，
/// [holes] 是它们在卡片里的位置，按卡片宽高的比例；画快照时这些地方留空，同
/// 一个东西不出现两份。
final class ZoomPicture {
  ZoomPicture(this.image, this.holes);

  final ui.Image image;
  final List<Rect> holes;

  void dispose() => image.dispose();
}

/// 页面用来拍下入口卡片、在飞行期间藏起它。
abstract interface class ZoomSourceHandle {
  /// 它最近一次画出来的样子，按 [pixelRatio] 取像素；拍不到时为 null。
  ui.Image? snapshot(double pixelRatio);

  /// 同一张卡片可能先后被几个页面藏起，都放开才重新画出来。
  void hide(Object by);
  void show(Object by);
}

class _ZoomSourceState extends State<ZoomSource> implements ZoomSourceHandle {
  final _hiding = GlobalKey();
  final _boundary = GlobalKey();
  final _hiders = <Object>{};

  List<Rect> _sharedParts() {
    final card = context.findRenderObject();
    if (card is! RenderBox || !card.hasSize || card.size.isEmpty) {
      return const [];
    }
    final parts = <Rect>[];
    void visit(Element element) {
      if (element.widget is! Hero) {
        element.visitChildren(visit);
        return;
      }
      final box = element.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final rect = MatrixUtils.transformRect(
        box.getTransformTo(card),
        Offset.zero & box.size,
      );
      final size = card.size;
      parts.add(
        Rect.fromLTRB(
          rect.left / size.width,
          rect.top / size.height,
          rect.right / size.width,
          rect.bottom / size.height,
        ),
      );
    }

    context.visitChildElements(visit);
    return parts;
  }

  @override
  ui.Image? snapshot(double pixelRatio) {
    final boundary = _boundary.currentContext?.findRenderObject();
    return boundary is _RenderSnapshot ? boundary.capture(pixelRatio) : null;
  }

  // 页面在构建阶段创建，这里只标记重绘，不重建。
  @override
  void hide(Object by) {
    _hiders.add(by);
    _sync();
  }

  @override
  void show(Object by) {
    _hiders.remove(by);
    _sync();
  }

  void _sync() {
    final hiding = _hiding.currentContext?.findRenderObject();
    if (hiding is _RenderHiding) hiding.hidden = _hiders.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) => _Hiding(
    key: _hiding,
    hidden: _hiders.isNotEmpty,
    child: _Snapshot(key: _boundary, child: widget.child),
  );
}

class _Hiding extends SingleChildRenderObjectWidget {
  const _Hiding({required this.hidden, super.key, super.child});

  final bool hidden;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHiding()..hidden = hidden;

  @override
  void updateRenderObject(BuildContext context, _RenderHiding renderObject) {
    renderObject.hidden = hidden;
  }
}

// 藏起时只是不画：下面的图层照样保留、照样更新，拍快照不受影响；读屏和点按
// 也照旧。
class _RenderHiding extends RenderProxyBox {
  bool _hidden = false;
  set hidden(bool value) {
    if (value == _hidden) return;
    _hidden = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_hidden) super.paint(context, offset);
  }
}

class _Snapshot extends SingleChildRenderObjectWidget {
  const _Snapshot({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSnapshot();
}

// 页面在构建阶段创建，这时卡片可能正因为按下的墨迹待重绘；用它上一帧画好的
// 图层，不等重绘。
class _RenderSnapshot extends RenderRepaintBoundary {
  ui.Image? capture(double pixelRatio) {
    final layer = this.layer;
    if (layer is! OffsetLayer || !hasSize) return null;
    try {
      return layer.toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
    } on Object {
      return null;
    }
  }
}
