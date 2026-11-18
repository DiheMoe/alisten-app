import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';

/// 从一个矩形长成自己的外框：菜单从按钮长出，页面和面板从被点的元素长出。
///
/// 子组件按自己的最终大小排版；绘制时外框从 [startRect] 插值到 [endRect]，
/// [growth] 为 0 时在起点，为 1 时在终点，弹簧冲过 1 时略大一点。内容缩放到
/// 盖满外框，[contentAnchor] 对着外框上的同一个锚点，裁在圆角外框里。
abstract class RenderMorph extends RenderProxyBox {
  RenderMorph({
    required this._growth,
    required this._fill,
    required this._border,
    required this._shadow,
    required this._contentAnchor,
  });

  double get growth => _growth;
  double _growth;
  set growth(double value) {
    if (value == _growth) return;
    _growth = value;
    markNeedsPaint();
  }

  Color get fill => _fill;
  Color _fill;
  set fill(Color value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  Color get border => _border;
  Color _border;
  set border(Color value) {
    if (value == _border) return;
    _border = value;
    markNeedsPaint();
  }

  BoxShadow? get shadow => _shadow;
  BoxShadow? _shadow;
  set shadow(BoxShadow? value) {
    if (value == _shadow) return;
    _shadow = value;
    markNeedsPaint();
  }

  Alignment get contentAnchor => _contentAnchor;
  Alignment _contentAnchor;
  set contentAnchor(Alignment value) {
    if (value == _contentAnchor) return;
    _contentAnchor = value;
    markNeedsPaint();
  }

  /// 起点和终点，在自身坐标里。
  Rect get startRect;
  Rect get endRect => Offset.zero & size;

  /// [shape] 外框此刻的圆角。
  BorderRadius radiusOf(Rect shape);

  /// 停在终点、不需要裁切时直接绘制子组件，不额外花绘制。
  bool get atRest => false;

  final _clipLayer = LayerHandle<ClipRRectLayer>();
  final _transformLayer = LayerHandle<TransformLayer>();

  /// 当前外框，在自身坐标里。
  Rect get shape {
    final start = startRect;
    final end = endRect;
    final left = lerpDouble(start.left, end.left, _growth)!;
    final top = lerpDouble(start.top, end.top, _growth)!;
    final right = lerpDouble(start.right, end.right, _growth)!;
    final bottom = lerpDouble(start.bottom, end.bottom, _growth)!;
    return Rect.fromLTRB(
      left,
      top,
      math.max(left, right),
      math.max(top, bottom),
    );
  }

  /// 当前圆角。
  BorderRadius get radius => radiusOf(shape);

  RRect _outline(Rect shape) => radiusOf(shape).toRRect(shape).scaleRadii();

  /// 把按最终大小排版的内容放进 [shape]。
  Matrix4 contentTransform(Rect shape) {
    if (size.isEmpty) return Matrix4.identity();
    final scale = math.max(
      shape.width / size.width,
      shape.height / size.height,
    );
    final from = _contentAnchor.alongSize(size);
    final to = _contentAnchor.withinRect(shape);
    return Matrix4.translationValues(to.dx, to.dy, 0)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-from.dx, -from.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (atRest) {
      _clipLayer.layer = null;
      _transformLayer.layer = null;
      if (child != null) context.paintChild(child, offset);
      return;
    }
    final shape = this.shape;
    final outline = _outline(shape);
    paintSurface(context.canvas, offset, outline);

    if (child == null) {
      _clipLayer.layer = null;
      _transformLayer.layer = null;
    } else {
      _clipLayer.layer = context.pushClipRRect(
        needsCompositing,
        offset,
        shape,
        outline,
        (context, offset) {
          _transformLayer.layer = context.pushTransform(
            needsCompositing,
            offset,
            contentTransform(shape),
            (context, offset) => context.paintChild(child, offset),
            oldLayer: _transformLayer.layer,
          );
        },
        oldLayer: _clipLayer.layer,
      );
    }

    paintBorder(context.canvas, offset, outline, _border);
  }

  /// 内容下面的底：阴影和底色。
  void paintSurface(Canvas canvas, Offset offset, RRect outline) {
    final shadow = _shadow;
    if (shadow != null && shadow.color.a > 0) {
      canvas.drawRRect(
        outline.shift(offset + shadow.offset).inflate(shadow.spreadRadius),
        shadow.toPaint(),
      );
    }
    if (_fill.a > 0) {
      canvas.drawRRect(outline.shift(offset), Paint()..color = _fill);
    }
  }

  /// 内容上面的描边。
  void paintBorder(Canvas canvas, Offset offset, RRect outline, Color color) {
    if (color.a <= 0) return;
    canvas.drawRRect(
      outline.shift(offset).deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (atRest) return super.hitTestChildren(result, position: position);
    final child = this.child;
    if (child == null) return false;
    final shape = this.shape;
    if (!_outline(shape).contains(position)) return false;
    return result.addWithPaintTransform(
      transform: contentTransform(shape),
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (atRest) return;
    transform.multiply(contentTransform(shape));
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      atRest ? null : shape;

  @override
  void dispose() {
    _clipLayer.layer = null;
    _transformLayer.layer = null;
    super.dispose();
  }
}
