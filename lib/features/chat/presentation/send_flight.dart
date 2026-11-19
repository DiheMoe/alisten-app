import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderDecoratedBox, RenderEditable;

/// 发送那一刻的输入框和里面那段文字：输入框的外形和颜色，文字在屏幕上的位置、
/// 排版宽度、可见的范围和样式，飞行从这里开始。
final class FlightSource {
  const FlightSource({
    required this.field,
    required this.fieldRadius,
    required this.fieldFill,
    required this.fieldStroke,
    required this.text,
    required this.origin,
    required this.visible,
    required this.wrapWidth,
    required this.style,
    required this.strut,
    required this.textScaler,
  });

  /// 整个输入框，飞出去的就是它。
  final Rect field;
  final BorderRadius fieldRadius;
  final Color fieldFill;
  final Color fieldStroke;

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

// 输入框里的样子在前 35% 的路程里淡去；气泡的样子在 10% 到 45% 之间出现。
// 短消息两种样子排版相同，看起来就是同一段字一边飞一边变色。
const _inputGoneAt = 0.35;
const _bubbleFrom = 0.1;
const _bubbleAt = 0.45;

// 底色在前一半路程里从输入框的颜色变成气泡的颜色，描边同时淡去。
const _fillBy = 0.5;

/// 刚发出的消息连同整个输入框飞进时间线。
///
/// 外框从输入框变成时间线上的气泡：位置、大小和圆角一起过渡，底色从输入框的
/// 颜色渐变成气泡的颜色。里面叠着两种样子：按输入框宽度排的原文，起飞时与输入
/// 框里的一模一样，随后淡去；按气泡宽度排的气泡内容，渐渐显出，落地时与真正的
/// 气泡重合，随后由它接替。两种样子都不缩放，只随文字的起点一起移动；长消息两边
/// 换行不同，也是平滑地从一种样子变成另一种，不会起飞就跳一下。
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
    this.onArrived,
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

  /// 飞行中的气泡第一次到达落点时调用一次，这时它还在轻轻回弹，没有停稳；
  /// 停稳后才调用 [onLanded]。
  final VoidCallback? onArrived;

  /// 飞行只画在这块区域里（时间线和输入框），每帧重新取；为 null 时不限制。
  /// 消息比时间线还高时，落点也只取气泡在这块区域里看得见的部分。
  final Rect? Function()? bounds;

  @override
  State<SendFlight> createState() => _SendFlightState();
}

class _SendFlightState extends State<SendFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress =
      AnimationController.unbounded(vsync: this)
        ..addListener(() {
          if (_progress.value >= 1) _arrive();
        })
        ..addStatusListener((status) {
          if (status.isCompleted) _land();
        });
  FlightTarget? _last;
  int _waited = 0;
  bool _arrived = false;
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

  void _arrive() {
    if (_arrived) return;
    _arrived = true;
    widget.onArrived?.call();
  }

  void _land() {
    if (_landed) return;
    _arrive();
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
    final start = source.field;
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
        final radius = target == null
            ? source.fieldRadius
            : BorderRadius.lerp(source.fieldRadius, target.radius, progress)!;
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
        // 文字的起点从输入框里移到气泡里，两种样子都从这里排。
        final textAt = target == null
            ? source.origin
            : Offset.lerp(
                source.origin,
                target.rect.topLeft + padding.topLeft,
                progress,
              )!;
        final at = textAt - shape.topLeft;
        final flight = Positioned.fromRect(
          rect: clip == null ? local : local.shift(-clip.topLeft),
          child: IgnorePointer(
            child: ExcludeSemantics(
              // Overlay 里没有 Material，文字会带上缺少 Material 时的下划线
              // 样式；透明的 Material 给出与时间线里气泡相同的文字样式。
              child: Material(
                type: MaterialType.transparency,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: lerpPremultiplied(
                      source.fieldFill,
                      widget.fill,
                      filled,
                    ),
                    borderRadius: radius,
                    border: Border.all(
                      color: source.fieldStroke.withValues(
                        alpha: source.fieldStroke.a * (1 - filled),
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (inputShown > 0)
                          Positioned(
                            left: at.dx,
                            top: at.dy,
                            child: Opacity(
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
                            left: at.dx,
                            top: at.dy,
                            child: Opacity(
                              opacity: bubbleShown,
                              child: SizedBox(
                                width: target.rect.width - padding.horizontal,
                                child: Text(
                                  widget.text,
                                  style: widget.textStyle,
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

/// 发送那一刻的输入框：[field] 是画出输入框外形的 [DecoratedBox]，在它下面找到
/// 文字的渲染对象，量出整段文字和看得见的范围。
FlightSource? flightSourceOf(RenderObject? field, {required String text}) {
  if (field is! RenderDecoratedBox || text.isEmpty || !field.hasSize) {
    return null;
  }
  final decoration = field.decoration;
  if (decoration is! BoxDecoration) return null;
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
  final border = decoration.border;
  return FlightSource(
    field: MatrixUtils.transformRect(
      field.getTransformTo(null),
      Offset.zero & field.size,
    ),
    fieldRadius:
        decoration.borderRadius?.resolve(found.textDirection) ??
        BorderRadius.zero,
    fieldFill: decoration.color ?? const Color(0x00000000),
    fieldStroke: border is Border ? border.top.color : const Color(0x00000000),
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
