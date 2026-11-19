import 'dart:math' as math;
import 'dart:ui' as ui show Image;

import 'package:alisten/shared/ui/morph.dart';
import 'package:flutter/widgets.dart';

/// 从屏幕上的一个元素长成自己的外框，页面和面板用。
///
/// [from] 是起点的全局矩形；为 null 时起点是终点向下平移 [riseBy]，即从底部
/// 升起。终点是自身边界绕中心缩放 [scale] 再平移 [offset]，拖动时用它。圆角从
/// [fromRadius]（不超过外框短边的一半）过渡到 [toRadius]。
///
/// 停在终点时只有 [clipAtRest] 为 true 才裁切，否则直接绘制子组件。
class ZoomFrame extends SingleChildRenderObjectWidget {
  const ZoomFrame({
    required this.growth,
    required this.from,
    required this.riseBy,
    required this.fromRadius,
    required this.toRadius,
    required this.clipAtRest,
    required this.fill,
    this.offset = Offset.zero,
    this.scale = 1,
    this.contentAnchor = Alignment.topCenter,
    this.picture,
    this.pictured = 0,
    super.child,
    super.key,
  });

  final double growth;
  final Rect? from;
  final double riseBy;
  final double fromRadius;
  final BorderRadius toRadius;
  final bool clipAtRest;
  final Color fill;
  final Offset offset;
  final double scale;
  final Alignment contentAnchor;

  /// 盖在页面上的起点元素的样子，按外框宽度缩放、对齐外框顶边，不透明度是
  /// [pictured]。
  final ui.Image? picture;
  final double pictured;

  @override
  RenderZoomFrame createRenderObject(BuildContext context) => RenderZoomFrame(
    growth: growth,
    from: from,
    riseBy: riseBy,
    fromRadius: fromRadius,
    toRadius: toRadius,
    clipAtRest: clipAtRest,
    fill: fill,
    offset: offset,
    scale: scale,
    contentAnchor: contentAnchor,
    picture: picture,
    pictured: pictured,
  );

  @override
  void updateRenderObject(BuildContext context, RenderZoomFrame renderObject) {
    renderObject
      ..growth = growth
      ..from = from
      ..riseBy = riseBy
      ..fromRadius = fromRadius
      ..toRadius = toRadius
      ..clipAtRest = clipAtRest
      ..fill = fill
      ..offset = offset
      ..scale = scale
      ..contentAnchor = contentAnchor
      ..picture = picture
      ..pictured = pictured;
  }
}

class RenderZoomFrame extends RenderMorph {
  RenderZoomFrame({
    required super.growth,
    required this._from,
    required this._riseBy,
    required this._fromRadius,
    required this._toRadius,
    required this._clipAtRest,
    required super.fill,
    required this._offset,
    required this._scale,
    required super.contentAnchor,
    required this._picture,
    required this._pictured,
  }) : super(border: const Color(0x00000000), shadow: null);

  ui.Image? get picture => _picture;
  ui.Image? _picture;
  set picture(ui.Image? value) {
    if (value == _picture) return;
    _picture = value;
    markNeedsPaint();
  }

  double get pictured => _pictured;
  double _pictured;
  set pictured(double value) {
    if (value == _pictured) return;
    _pictured = value;
    markNeedsPaint();
  }

  @override
  void paintCover(Canvas canvas, Offset offset, Rect shape, RRect outline) {
    final picture = _picture;
    if (picture == null || _pictured <= 0 || picture.width == 0) return;
    final width = shape.width;
    final height = width * picture.height / picture.width;
    canvas
      ..save()
      ..clipRRect(outline.shift(offset))
      ..drawImageRect(
        picture,
        Offset.zero & Size(picture.width.toDouble(), picture.height.toDouble()),
        Rect.fromLTWH(shape.left, shape.top, width, height).shift(offset),
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, _pictured.clamp(0, 1))
          ..filterQuality = FilterQuality.medium,
      )
      ..restore();
  }

  Rect? get from => _from;
  Rect? _from;
  set from(Rect? value) {
    if (value == _from) return;
    _from = value;
    markNeedsPaint();
  }

  double get riseBy => _riseBy;
  double _riseBy;
  set riseBy(double value) {
    if (value == _riseBy) return;
    _riseBy = value;
    markNeedsPaint();
  }

  double get fromRadius => _fromRadius;
  double _fromRadius;
  set fromRadius(double value) {
    if (value == _fromRadius) return;
    _fromRadius = value;
    markNeedsPaint();
  }

  BorderRadius get toRadius => _toRadius;
  BorderRadius _toRadius;
  set toRadius(BorderRadius value) {
    if (value == _toRadius) return;
    _toRadius = value;
    markNeedsPaint();
  }

  bool get clipAtRest => _clipAtRest;
  bool _clipAtRest;
  set clipAtRest(bool value) {
    if (value == _clipAtRest) return;
    _clipAtRest = value;
    markNeedsPaint();
  }

  Offset get offset => _offset;
  Offset _offset;
  set offset(Offset value) {
    if (value == _offset) return;
    _offset = value;
    markNeedsPaint();
  }

  double get scale => _scale;
  double _scale;
  set scale(double value) {
    if (value == _scale) return;
    _scale = value;
    markNeedsPaint();
  }

  @override
  bool get atRest =>
      !_clipAtRest && growth == 1 && _offset == Offset.zero && _scale == 1;

  @override
  Rect get endRect {
    final bounds = Offset.zero & size;
    return Rect.fromCenter(
      center: bounds.center + _offset,
      width: bounds.width * _scale,
      height: bounds.height * _scale,
    );
  }

  @override
  Rect get startRect {
    final from = _from;
    if (from == null) return endRect.shift(Offset(0, _riseBy));
    final toLocal = Matrix4.tryInvert(getTransformTo(null));
    return toLocal == null ? from : MatrixUtils.transformRect(toLocal, from);
  }

  @override
  BorderRadius radiusOf(Rect shape) {
    final start = BorderRadius.circular(
      math.min(_fromRadius, shape.shortestSide / 2),
    );
    return BorderRadius.lerp(start, _toRadius, growth.clamp(0, 1))!;
  }
}
