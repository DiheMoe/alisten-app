import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 横向分页滑到两页之间时，在左右两侧 [extent] 宽的带内渐隐，滑出去的内容不在
/// 边界被齐齐切断。[position] 是页序号，滑动途中为小数。
///
/// 停在某一页时不渐隐，也不离屏绘制：这时没有内容伸到边界外。
class SideFade extends SingleChildRenderObjectWidget {
  const SideFade({
    required this.position,
    required this.extent,
    required Widget super.child,
    super.key,
  });

  final ValueListenable<double> position;
  final double extent;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSideFade(position: position, extent: extent);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSideFade)
      ..position = position
      ..extent = extent;
  }
}

const _opaque = Color(0xFFFFFFFF);
const _clear = Color(0x00FFFFFF);

// 页面停稳时位置不一定正好是整数。
const _settled = 0.001;

class _RenderSideFade extends RenderProxyBox {
  _RenderSideFade({required this._position, required this._extent});

  ValueListenable<double> _position;
  set position(ValueListenable<double> value) {
    if (identical(value, _position)) return;
    if (attached) _position.removeListener(_moved);
    _position = value;
    if (attached) value.addListener(_moved);
    _moved();
  }

  double _extent;
  set extent(double value) {
    if (value == _extent) return;
    _extent = value;
    markNeedsPaint();
  }

  bool _between = false;

  // 位置可能在构建和布局期间更新，这里只能重绘。
  void _moved() {
    final at = _position.value;
    final between = (at - at.roundToDouble()).abs() > _settled;
    if (between == _between) return;
    _between = between;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position.addListener(_moved);
    _moved();
  }

  @override
  void detach() {
    _position.removeListener(_moved);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || !_between || size.width <= 2 * _extent) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final edge = _extent / size.width;
    final mask = layer ?? ShaderMaskLayer();
    mask
      ..shader = LinearGradient(
        colors: const [_clear, _opaque, _opaque, _clear],
        stops: [0, edge, 1 - edge, 1],
      ).createShader(Offset.zero & size)
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(mask, super.paint, offset);
    layer = mask;
  }
}
