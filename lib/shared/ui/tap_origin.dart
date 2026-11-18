import 'package:flutter/widgets.dart';

/// 一次点按：被点的元素在屏幕上的位置和圆角，是接下来打开的页面或面板的起点。
final class LaunchOrigin {
  LaunchOrigin._(RenderBox box, {required this.radius})
    : rect = _globalRect(box),
      _box = WeakReference(box);

  /// 不跟随任何元素的起点。
  LaunchOrigin.at(this.rect, {this.radius = 0}) : _box = null;

  /// 点按时的位置。
  final Rect rect;
  final double radius;
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

  static void record(BuildContext context, {double radius = 0}) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    _last = LaunchOrigin._(box, radius: radius);
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

  @override
  State<ZoomTarget> createState() => _ZoomTargetState();
}

class _ZoomTargetState extends State<ZoomTarget> {
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
  Widget build(BuildContext context) => widget.child;
}
