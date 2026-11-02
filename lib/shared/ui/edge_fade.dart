import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 在 [child] 顶部 [top]、底部 [bottom] 高的固定带内渐隐 [EdgeFadeItem]，其他
/// 内容不渐隐。
///
/// 只有伸进带里的条目各自离屏绘制，而不把整个 [child] 画进离屏缓冲：输入法显示
/// 时系统每帧都要合成键盘和本应用，整块离屏会让每帧多画一遍整个视口。
class EdgeFade extends SingleChildRenderObjectWidget {
  const EdgeFade({
    required Widget super.child,
    this.top = 0,
    this.bottom = 0,
    super.key,
  }) : assert(top >= 0 && bottom >= 0);

  final double top;
  final double bottom;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderEdgeFade(top: top, bottom: bottom);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderEdgeFade)
      ..top = top
      ..bottom = bottom;
  }
}

/// 条目与所在滚动视口之间不能有重绘边界：滚动时只重绘视口，边界里的条目不会
/// 重绘，渐隐就停在旧位置。列表须关闭自动添加的重绘边界，需要时把边界放在条目
/// 内部。
class EdgeFadeItem extends SingleChildRenderObjectWidget {
  const EdgeFadeItem({required Widget super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderEdgeFadeItem();
  }
}

const _opaque = Color(0xFFFFFFFF);
const _clear = Color(0x00FFFFFF);

class _RenderEdgeFade extends RenderProxyBox {
  _RenderEdgeFade({required this._top, required this._bottom});

  double _top;
  set top(double value) {
    if (value == _top) return;
    _top = value;
    _repaintItems();
  }

  double _bottom;
  set bottom(double value) {
    if (value == _bottom) return;
    _bottom = value;
    _repaintItems();
  }

  ui.Shader? _shader;
  (double, double, double)? _shaderKey;

  // 条目在视口的重绘边界内，本对象重绘时不会带动它们，带高变化须逐个标记重绘。
  void _repaintItems() {
    void visit(RenderObject node) {
      if (node is _RenderEdgeFadeItem) node.markNeedsPaint();
      node.visitChildren(visit);
    }

    visitChildren(visit);
  }

  double get _topBand => math.min(_top, size.height / 2);
  double get _bottomBand => math.min(_bottom, size.height / 2);

  // 遮罩取本对象在 [item] 坐标中的范围，条目超出自身边界绘制的部分（如发光）
  // 也一起渐隐；离屏缓冲大小由引擎按实际绘制范围决定，不随遮罩变大。
  Rect? _maskFor(RenderBox item) {
    final height = size.height;
    final top = _topBand;
    final bottom = _bottomBand;
    if (top <= 0 && bottom <= 0) return null;
    final toFade = item.getTransformTo(this);
    if (toFade.determinant() == 0) return null;
    final bounds = MatrixUtils.transformRect(toFade, Offset.zero & item.size);
    if (bounds.bottom <= 0 || bounds.top >= height) return null;
    final inTop = top > 0 && bounds.top < top;
    final inBottom = bottom > 0 && bounds.bottom > height - bottom;
    if (!inTop && !inBottom) return null;
    return MatrixUtils.inverseTransformRect(toFade, Offset.zero & size);
  }

  ui.Shader _shaderOver(double height) {
    final top = _topBand / size.height;
    final bottom = _bottomBand / size.height;
    final key = (height, top, bottom);
    if (_shader case final shader? when key == _shaderKey) return shader;
    _shaderKey = key;
    return _shader = ui.Gradient.linear(
      Offset.zero,
      Offset(0, height),
      [
        top > 0 ? _clear : _opaque,
        _opaque,
        _opaque,
        bottom > 0 ? _clear : _opaque,
      ],
      [0, top, 1 - bottom, 1],
    );
  }
}

class _RenderEdgeFadeItem extends RenderProxyBox {
  // 是否推入遮罩图层取决于滚动位置，绘制时才知道；祖先若按无需合成的方式绘制，
  // 推入的图层会逃出它们的裁剪。
  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final fade = child == null ? null : _fade();
    assert(fade == null || _debugRepaintedWithViewport(fade));
    final mask = fade?._maskFor(this);
    if (fade == null || mask == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final masking = (layer as ShaderMaskLayer?) ?? ShaderMaskLayer();
    layer = masking
      ..shader = fade._shaderOver(mask.height)
      ..maskRect = mask.shift(offset)
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(masking, super.paint, offset);
  }

  _RenderEdgeFade? _fade() {
    for (var node = parent; node != null; node = node.parent) {
      if (node is _RenderEdgeFade) return node;
    }
    return null;
  }

  bool _debugRepaintedWithViewport(_RenderEdgeFade fade) {
    for (
      var node = parent;
      node != null && node != fade && node is! RenderAbstractViewport;
      node = node.parent
    ) {
      if (node.isRepaintBoundary) {
        throw FlutterError.fromParts([
          ErrorSummary(
            'An EdgeFadeItem sits under a repaint boundary inside its '
            'scrolling viewport.',
          ),
          ErrorDescription(
            'Scrolling repaints only the viewport, so the item would keep the '
            'fade of where it was painted last.',
          ),
          ErrorHint(
            'Turn off the repaint boundaries the list adds '
            '(addRepaintBoundaries: false) and put any RepaintBoundary inside '
            'the EdgeFadeItem.',
          ),
          DiagnosticsProperty<RenderObject>('The repaint boundary was', node),
        ]);
      }
    }
    return true;
  }
}
