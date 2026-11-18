import 'dart:math' as math;
import 'dart:ui' as ui show FragmentShader, Image;
import 'dart:ui' show lerpDouble;

import 'package:alisten/shared/ui/drop.dart';
import 'package:alisten/shared/ui/morph.dart';
import 'package:flutter/widgets.dart';

/// 从触发按钮的外形长成的菜单面板。
///
/// [growth] 为 0 时外框与按钮重合，为 1 时就是面板本身。圆角在当前外框的
/// 胶囊半径（短边的一半）和 [radius] 之间按 [corners] 插值。胶囊半径跟着外框
/// 变化，所以从胶囊收成卡片是连续的，不会停在胶囊上再突然变方。
///
/// 给了 [pour] 时改为液滴：菜单主体和按钮变成的水滴融成一体，见 [Pour]；
/// [glyph] 是按钮的样子，画在水滴里。
class MorphPanel extends SingleChildRenderObjectWidget {
  const MorphPanel({
    required this.growth,
    required this.corners,
    required this.trigger,
    required this.triggerAnchor,
    required this.panelAnchor,
    required this.offset,
    required this.radius,
    required this.fill,
    required this.border,
    required this.shadow,
    this.pour,
    this.glyph,
    super.child,
    super.key,
  });

  final double growth;

  /// 0 是胶囊，1 是 [radius] 圆角的卡片。
  final double corners;

  /// 触发按钮的大小。两者的相对位置按 [CompositedTransformFollower] 的规则算：
  /// 面板的 [panelAnchor] 点落在按钮的 [triggerAnchor] 点再加 [offset] 处。
  final Size trigger;
  final Alignment triggerAnchor;
  final Alignment panelAnchor;
  final Offset offset;
  final double radius;
  final Color fill;
  final Color border;
  final BoxShadow shadow;
  final Pour? pour;
  final ui.Image? glyph;

  @override
  RenderMorphPanel createRenderObject(BuildContext context) => RenderMorphPanel(
    growth: growth,
    corners: corners,
    trigger: trigger,
    triggerAnchor: triggerAnchor,
    panelAnchor: panelAnchor,
    offset: offset,
    radius: radius,
    fill: fill,
    border: border,
    shadow: shadow,
    pour: pour,
    glyph: glyph,
    pixel: 1 / (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1),
  );

  @override
  void updateRenderObject(BuildContext context, RenderMorphPanel renderObject) {
    renderObject
      ..growth = growth
      ..corners = corners
      ..trigger = trigger
      ..triggerAnchor = triggerAnchor
      ..contentAnchor = panelAnchor
      ..offset = offset
      ..cardRadius = radius
      ..fill = fill
      ..border = border
      ..shadow = shadow
      ..pour = pour
      ..glyph = glyph
      ..pixel = 1 / (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1);
  }
}

class RenderMorphPanel extends RenderMorph {
  RenderMorphPanel({
    required super.growth,
    required this._corners,
    required this._trigger,
    required this._triggerAnchor,
    required Alignment panelAnchor,
    required this._offset,
    required double radius,
    required super.fill,
    required super.border,
    required BoxShadow super.shadow,
    this._pour,
    this._glyph,
    this._pixel = 1,
  }) : _cardRadius = radius,
       super(contentAnchor: panelAnchor);

  Pour? get pour => _pour;
  Pour? _pour;
  set pour(Pour? value) {
    if (value == _pour) return;
    _pour = value;
    markNeedsPaint();
  }

  ui.Image? get glyph => _glyph;
  ui.Image? _glyph;
  set glyph(ui.Image? value) {
    if (value == _glyph) return;
    _glyph = value;
    markNeedsPaint();
  }

  double get pixel => _pixel;
  double _pixel;
  set pixel(double value) {
    if (value == _pixel) return;
    _pixel = value;
    markNeedsPaint();
  }

  ui.FragmentShader? _shader;

  /// 液滴此刻的样子，没在倒出或收回时为 null。
  DropFrame? get dropFrame {
    final pour = _pour;
    if (pour == null || !hasSize || size.isEmpty) return null;
    return dropFrameOf(
      pour,
      anchor: startRect,
      card: Offset.zero & size,
      cardRadius: _cardRadius,
    );
  }

  double get corners => _corners;
  double _corners;
  set corners(double value) {
    if (value == _corners) return;
    _corners = value;
    markNeedsPaint();
  }

  Size get trigger => _trigger;
  Size _trigger;
  set trigger(Size value) {
    if (value == _trigger) return;
    _trigger = value;
    markNeedsPaint();
  }

  Alignment get triggerAnchor => _triggerAnchor;
  Alignment _triggerAnchor;
  set triggerAnchor(Alignment value) {
    if (value == _triggerAnchor) return;
    _triggerAnchor = value;
    markNeedsPaint();
  }

  Offset get offset => _offset;
  Offset _offset;
  set offset(Offset value) {
    if (value == _offset) return;
    _offset = value;
    markNeedsPaint();
  }

  double get cardRadius => _cardRadius;
  double _cardRadius;
  set cardRadius(double value) {
    if (value == _cardRadius) return;
    _cardRadius = value;
    markNeedsPaint();
  }

  @override
  Rect get startRect =>
      (contentAnchor.alongSize(size) -
          _offset -
          _triggerAnchor.alongSize(_trigger)) &
      _trigger;

  @override
  Rect get shape => dropFrame?.body ?? super.shape;

  @override
  BorderRadius radiusOf(Rect shape) {
    if (dropFrame case final frame?) {
      return BorderRadius.circular(frame.bodyRadius);
    }
    final capsule = shape.shortestSide / 2;
    return BorderRadius.circular(
      math.min(
        lerpDouble(capsule, _cardRadius, _corners.clamp(0, 1))!,
        capsule,
      ),
    );
  }

  // 内容按卡片排版，以主体中心缩放：倒出时按宽度，收回时整个放得下。
  @override
  Matrix4 contentTransform(Rect shape) {
    final pour = _pour;
    if (pour == null || size.isEmpty) return super.contentTransform(shape);
    final scale = switch (pour) {
      PourOut() => shape.width / size.width,
      PourBack() => math.min(
        shape.width / size.width,
        shape.height / size.height,
      ),
    };
    final card = (Offset.zero & size).center;
    return Matrix4.translationValues(shape.center.dx, shape.center.dy, 0)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-card.dx, -card.dy, 0, 1);
  }

  @override
  void paintSurface(Canvas canvas, Offset offset, RRect outline) {
    final frame = dropFrame;
    if (frame == null) {
      super.paintSurface(canvas, offset, outline);
      return;
    }
    final shadow = this.shadow;
    if (shadow != null && shadow.color.a > 0 && frame.lift > 0) {
      canvas.drawRRect(
        outline.shift(offset + shadow.offset).inflate(shadow.spreadRadius),
        shadow.toPaint()
          ..color = shadow.color.withValues(alpha: shadow.color.a * frame.lift),
      );
    }
    final program = Goo.program;
    if (program != null) _shader ??= program.fragmentShader();
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    paintGoo(
      canvas,
      frame,
      fill.withValues(alpha: fill.a * frame.solid),
      shader: _shader,
      pixel: _pixel,
    );
    if (_glyph case final glyph?) paintGlyph(canvas, glyph, frame);
    canvas.restore();
  }

  @override
  void paintBorder(Canvas canvas, Offset offset, RRect outline, Color color) {
    final frame = dropFrame;
    super.paintBorder(
      canvas,
      offset,
      outline,
      frame == null ? color : color.withValues(alpha: color.a * frame.rim),
    );
  }

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }
}
