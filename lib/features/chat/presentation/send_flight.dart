import 'package:alisten/shared/theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;

/// 输入框里那段文字：在屏幕上的位置、排版宽度、可见的范围和颜色，飞行从这里
/// 开始。
final class FlightSource {
  const FlightSource({
    required this.text,
    required this.origin,
    required this.visible,
    required this.wrapWidth,
    required this.style,
    required this.strut,
    required this.textScaler,
  });

  /// 整段文字的外框，滚出输入框的部分也算在内。
  final Rect text;

  /// 文字排版的原点：第一行的左上角往上、往左让出行距的位置，滚动已算在内。
  final Offset origin;

  /// 输入框里看得见文字的范围。
  final Rect visible;

  /// 输入框排版文字用的宽度、样式、行高和缩放，飞出时照样排，换行和行距才
  /// 与输入框里一样。
  final double wrapWidth;
  final TextStyle style;
  final StrutStyle? strut;
  final TextScaler textScaler;
}

/// 气泡落点：时间线上那个气泡此刻的位置和圆角。
typedef FlightTarget = ({Rect rect, BorderRadius radius});

// 等时间线把气泡排好最多等这么多帧，排不出来就不飞了。
const _waitFrames = 20;

// 输入框里的样子在前 35% 的路程里淡去；气泡的样子在 10% 到 45% 之间出现，
// 底色在前 35% 里铺满。短消息两种样子排版相同，看起来就是同一段字飞过去。
const _inputGoneAt = 0.35;
const _bubbleFrom = 0.1;
const _bubbleAt = 0.45;
const _fillBy = 0.35;

/// 刚发出的消息从输入框飞进时间线。
///
/// 外框从输入框里看得见的那段文字长到时间线上的气泡。里面叠着两种样子：按
/// 输入框宽度排的原文，起飞时与输入框里的一模一样，随外框缩放、淡去；按气泡
/// 宽度排的气泡内容，随外框缩放、显出，落地时与真正的气泡重合，随后由它接替。
/// 长消息两边换行不同，也是平滑地从一种样子变成另一种，不会起飞就跳一下。
///
/// 放在 [Overlay] 里。落点每帧重新测量，时间线滚动时也追得上。
class SendFlight extends StatefulWidget {
  const SendFlight({
    required this.text,
    required this.source,
    required this.target,
    required this.padding,
    required this.textStyle,
    required this.fill,
    required this.onLanded,
    this.bounds,
    super.key,
  });

  final String text;
  final FlightSource source;
  final FlightTarget? Function() target;

  /// 气泡的内边距。
  final EdgeInsets padding;

  /// 气泡里的文字样式，颜色是落地后的颜色。
  final TextStyle textStyle;
  final Color fill;
  final VoidCallback onLanded;

  /// 飞行只画在这块区域里（时间线和输入框），每帧重新取；为 null 时不限制。
  /// 消息比时间线还高时，落点也只取气泡在这块区域里看得见的部分。
  final Rect? Function()? bounds;

  @override
  State<SendFlight> createState() => _SendFlightState();
}

class _SendFlightState extends State<SendFlight>
    with SingleTickerProviderStateMixin {
  late final _progress = AnimationController.unbounded(vsync: this)
    ..addStatusListener((status) {
      if (status.isCompleted) _land();
    });
  FlightTarget? _last;
  int _waited = 0;
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_aim);
  }

  void _aim(Duration _) {
    if (!mounted) return;
    final target = widget.target();
    if (target != null) {
      setState(() => _last = target);
      _progress.animateWith(
        springTo(AlistenSprings.chatFlight, from: 0, to: 1),
      );
      return;
    }
    if (++_waited > _waitFrames) {
      _land();
      return;
    }
    WidgetsBinding.instance
      ..addPostFrameCallback(_aim)
      ..scheduleFrame();
  }

  void _land() {
    if (_landed) return;
    _landed = true;
    widget.onLanded();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final source = widget.source;
    final padding = widget.padding;
    // 起点是看得见的那段文字，外面套上气泡的内边距，形状才与落点对应。
    final start = padding.inflateRect(source.text.intersect(source.visible));
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        final progress = _progress.value;
        final target = widget.target() ?? _last;
        if (target != null) _last = target;
        final area = widget.bounds?.call();
        // 落点：气泡在区域里看得见的部分。长消息只露出最后几行，正好与输入框
        // 里光标所在的那几行对应。
        final end = target == null
            ? null
            : area == null || !area.overlaps(target.rect)
            ? target.rect
            : target.rect.intersect(area);
        final shape = end == null ? start : Rect.lerp(start, end, progress)!;
        Rect toLocal(Rect rect) => Rect.fromPoints(
          overlay.globalToLocal(rect.topLeft),
          overlay.globalToLocal(rect.bottomRight),
        );
        final clip = area == null ? null : toLocal(area);
        final local = toLocal(shape);
        final inputShown = 1 - (progress / _inputGoneAt).clamp(0.0, 1.0);
        final bubbleShown =
            ((progress - _bubbleFrom) / (_bubbleAt - _bubbleFrom)).clamp(
              0.0,
              1.0,
            );
        final filled = (progress / _fillBy).clamp(0.0, 1.0);
        // 两种样子都按外框的宽度缩放，左上角对着各自在外框里的位置。
        final inputScale = start.width <= 0 ? 1.0 : shape.width / start.width;
        final inputAt = (source.origin - start.topLeft) * inputScale;
        final bubbleScale = end == null || end.width <= 0
            ? 1.0
            : shape.width / end.width;
        // 气泡内容的左上角：落点之上被区域截掉的部分随外框一起缩放。
        final bubbleAt = target == null || end == null
            ? Offset.zero
            : (target.rect.topLeft - end.topLeft) * bubbleScale;
        final flight = Positioned.fromRect(
          rect: clip == null ? local : local.shift(-clip.topLeft),
          child: IgnorePointer(
            child: ExcludeSemantics(
              // Overlay 里没有 Material，文字会带上缺少 Material 时的下划线
              // 样式；透明的 Material 给出与时间线里气泡相同的文字样式。
              child: Material(
                type: MaterialType.transparency,
                child: ClipRRect(
                  borderRadius: target?.radius ?? BorderRadius.zero,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: widget.fill.withValues(
                            alpha: widget.fill.a * filled,
                          ),
                        ),
                      ),
                      if (inputShown > 0)
                        Positioned(
                          left: inputAt.dx,
                          top: inputAt.dy,
                          child: _Scaled(
                            scale: inputScale,
                            opacity: inputShown,
                            child: SizedBox(
                              width: source.wrapWidth,
                              child: Text(
                                widget.text,
                                style: source.style,
                                strutStyle: source.strut,
                                textScaler: source.textScaler,
                              ),
                            ),
                          ),
                        ),
                      if (target != null && bubbleShown > 0)
                        Positioned(
                          left: bubbleAt.dx,
                          top: bubbleAt.dy,
                          child: _Scaled(
                            scale: bubbleScale,
                            opacity: bubbleShown,
                            child: SizedBox(
                              width: target.rect.width,
                              child: Padding(
                                padding: padding,
                                child: Text(
                                  widget.text,
                                  style: widget.textStyle,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        if (clip == null) return flight;
        return Positioned.fromRect(
          rect: clip,
          child: ClipRect(
            child: Stack(clipBehavior: Clip.none, children: [flight]),
          ),
        );
      },
    );
  }
}

class _Scaled extends StatelessWidget {
  const _Scaled({
    required this.scale,
    required this.opacity,
    required this.child,
  });

  final double scale;
  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }
}

/// 输入框里那段文字：在 [field] 下面找到文字的渲染对象，量出整段文字和看得见
/// 的范围。
FlightSource? flightSourceOf(RenderObject? field, {required String text}) {
  if (field == null || text.isEmpty) return null;
  RenderEditable? editable;
  void visit(RenderObject child) {
    if (editable != null) return;
    if (child is RenderEditable) {
      editable = child;
      return;
    }
    child.visitChildren(visit);
  }

  visit(field);
  final found = editable;
  if (found == null || !found.attached || !found.hasSize) return null;
  final boxes = found.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  if (boxes.isEmpty) return null;
  var rect = boxes.first.toRect();
  for (final box in boxes.skip(1)) {
    rect = rect.expandToInclude(box.toRect());
  }
  final toGlobal = found.getTransformTo(null);
  final span = found.text;
  final style = span?.style;
  if (span == null || style == null) return null;
  final wrapWidth = found.size.width - found.cursorWidth - 1;
  // 选区框在输入框坐标里带着滚动偏移；照同样的样式再排一遍，量出第一行在文字
  // 里的位置，两者相减就是文字原点在输入框里的位置。
  final painter = TextPainter(
    text: span,
    textDirection: found.textDirection,
    textAlign: found.textAlign,
    strutStyle: found.strutStyle,
    textScaler: found.textScaler,
  )..layout(maxWidth: wrapWidth);
  final measured = painter.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
    boxHeightStyle: found.selectionHeightStyle,
    boxWidthStyle: found.selectionWidthStyle,
  );
  painter.dispose();
  if (measured.isEmpty) return null;
  final scrolled =
      boxes.first.toRect().topLeft - measured.first.toRect().topLeft;
  return FlightSource(
    text: MatrixUtils.transformRect(toGlobal, rect),
    origin: MatrixUtils.transformPoint(toGlobal, scrolled),
    visible: MatrixUtils.transformRect(toGlobal, Offset.zero & found.size),
    // 与输入框排版时一样，给光标留出位置。
    wrapWidth: wrapWidth,
    // 输入框的样式已合并了主题，不再继承外面的默认样式。
    style: style.copyWith(inherit: false),
    strut: found.strutStyle,
    textScaler: found.textScaler,
  );
}
