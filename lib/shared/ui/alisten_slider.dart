import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/material.dart';

/// 取值范围 0–1。拖动或点按时每次变化都调用 [onChanged]，松手后以最终值调用
/// [onChangeEnd]；读屏每次调整 0.1，并同时调用两者。
class AlistenSlider extends StatefulWidget {
  const AlistenSlider({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.onChangeEnd,
    super.key,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String semanticLabel;

  @override
  State<AlistenSlider> createState() => _AlistenSliderState();
}

const _trackHeight = AlistenSizes.sliderTrack;
const _thumbRadius = AlistenSizes.sliderThumb / 2;
const _heldThumbRadius = AlistenSizes.sliderThumbHeld / 2;
const _semanticStep = 0.1;

class _AlistenSliderState extends State<AlistenSlider> {
  bool _held = false;
  double? _last;

  double get _value => widget.value.clamp(0.0, 1.0);

  double _valueAt(Offset local, double width) {
    final travel = width - 2 * _heldThumbRadius;
    if (travel <= 0) return _value;
    final along = (local.dx - _heldThumbRadius) / travel;
    final value = Directionality.of(context) == TextDirection.rtl
        ? 1 - along
        : along;
    return value.clamp(0.0, 1.0);
  }

  void _change(double value) {
    _last = value;
    widget.onChanged?.call(value);
  }

  void _end() {
    final last = _last;
    _last = null;
    if (_held) setState(() => _held = false);
    if (last != null) widget.onChangeEnd?.call(last);
  }

  void _step(double by) {
    final value = (_value + by).clamp(0.0, 1.0);
    widget.onChanged?.call(value);
    widget.onChangeEnd?.call(value);
  }

  String _percent(double value) => '${(value * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final enabled = widget.onChanged != null;
    final value = _value;
    return Semantics(
      container: true,
      slider: true,
      enabled: enabled,
      label: widget.semanticLabel,
      value: _percent(value),
      increasedValue: _percent((value + _semanticStep).clamp(0.0, 1.0)),
      decreasedValue: _percent((value - _semanticStep).clamp(0.0, 1.0)),
      onIncrease: enabled ? () => _step(_semanticStep) : null,
      onDecrease: enabled ? () => _step(-_semanticStep) : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : AlistenSizes.sliderFallbackWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onHorizontalDragStart: enabled
                ? (details) {
                    setState(() => _held = true);
                    _change(_valueAt(details.localPosition, width));
                  }
                : null,
            onHorizontalDragUpdate: enabled
                ? (details) => _change(_valueAt(details.localPosition, width))
                : null,
            onHorizontalDragEnd: enabled ? (_) => _end() : null,
            onHorizontalDragCancel: enabled ? _end : null,
            onTapUp: enabled
                ? (details) {
                    _change(_valueAt(details.localPosition, width));
                    _end();
                  }
                : null,
            child: Opacity(
              opacity: enabled ? 1 : AlistenPress.disabledOpacity,
              child: CustomPaint(
                size: Size(width, AlistenSizes.minTouchTarget),
                painter: _SliderPainter(
                  value: value,
                  held: _held,
                  rtl: Directionality.of(context) == TextDirection.rtl,
                  ink: colors.onGlass,
                  empty: colors.outline,
                  shadow: Theme.of(context).colorScheme.shadow,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({
    required this.value,
    required this.held,
    required this.rtl,
    required this.ink,
    required this.empty,
    required this.shadow,
  });

  final double value;
  final bool held;
  final bool rtl;
  final Color ink;
  final Color empty;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    // 轨道两端按放大后的滑块半径内缩，滑块才不会超出控件。
    final start = _heldThumbRadius;
    final end = size.width - _heldThumbRadius;
    final along = start + (end - start) * value;
    final thumbX = rtl ? size.width - along : along;
    final track = RRect.fromLTRBR(
      start - _trackHeight / 2,
      centerY - _trackHeight / 2,
      end + _trackHeight / 2,
      centerY + _trackHeight / 2,
      const Radius.circular(_trackHeight / 2),
    );
    canvas.drawRRect(track, Paint()..color = empty);
    final filled = rtl
        ? RRect.fromLTRBR(
            thumbX,
            track.top,
            track.right,
            track.bottom,
            track.tlRadius,
          )
        : RRect.fromLTRBR(
            track.left,
            track.top,
            thumbX,
            track.bottom,
            track.tlRadius,
          );
    canvas.drawRRect(filled, Paint()..color = ink);
    final radius = held ? _heldThumbRadius : _thumbRadius;
    final thumb = Offset(thumbX, centerY);
    canvas
      ..drawCircle(
        thumb.translate(0, 1),
        radius,
        Paint()
          ..color = shadow.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..drawCircle(thumb, radius, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_SliderPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.held != held ||
        oldDelegate.rtl != rtl ||
        oldDelegate.ink != ink ||
        oldDelegate.empty != empty ||
        oldDelegate.shadow != shadow;
  }
}
