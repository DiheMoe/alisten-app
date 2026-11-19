import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// 相邻两个字开始显出的间隔；字多时缩短，整段在 _spread 秒内都开始显出。
const _stagger = 0.024;
const _spread = 0.26;

// 每个字从开始显出到停稳的秒数。
const _glyphTime = 0.32;

// 每个字从下方这么远升起、从这么大放大到原大，在前这么一段里淡入。
const _rise = 10.0;
const _scaleFrom = 0.6;
const _fadeShare = 0.5;

/// [GlyphCascade] 里整段文字都停稳所需的秒数。
const glyphCascadeSeconds = _spread + _glyphTime;

/// 共 [count] 个字时，第 [index] 个字在开始显出 [elapsed] 秒后显出了多少，从 0
/// 到 1。
double glyphShown(int index, int count, double elapsed) {
  final step = count > 1 ? math.min(_stagger, _spread / (count - 1)) : 0.0;
  return ((elapsed - index * step) / _glyphTime).clamp(0.0, 1.0);
}

/// 让 [child] 里的文字从左往右逐字弹出：每个字从下方升起、放大到原大并淡入。
///
/// 文字照常排版，每个字按它排好的位置裁出来画，停稳后与直接画出的一模一样。
/// 省略号不在原文里，算作最后一个字。
class GlyphCascade extends SingleChildRenderObjectWidget {
  const GlyphCascade({required this.elapsed, required super.child, super.key});

  /// 从开始显出算起的秒数；不到 0 时什么都不画。
  final double elapsed;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderGlyphCascade(elapsed);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlyphCascade renderObject,
  ) {
    renderObject.elapsed = elapsed;
  }
}

typedef _Glyph = ({Rect rect, int line});

class RenderGlyphCascade extends RenderProxyBox {
  RenderGlyphCascade(this._elapsed);

  double _elapsed;
  set elapsed(double value) {
    if (value == _elapsed) return;
    _elapsed = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _elapsed <= 0) return;
    if (_elapsed >= glyphCascadeSeconds) {
      context.paintChild(child, offset);
      return;
    }
    final glyphs = _glyphs();
    // 已经停稳的字连成一段画，免得一个字一个字裁开。
    Rect? settled;
    var settledLine = -1;
    void paintSettled() {
      final rect = settled;
      if (rect != null) _paintGlyph(context, offset, rect, 1);
      settled = null;
    }

    for (final (index, glyph) in glyphs.indexed) {
      final shown = glyphShown(index, glyphs.length, _elapsed);
      if (shown <= 0) break;
      if (shown >= 1) {
        if (glyph.line != settledLine) paintSettled();
        settledLine = glyph.line;
        settled = settled?.expandToInclude(glyph.rect) ?? glyph.rect;
        continue;
      }
      paintSettled();
      _paintGlyph(context, offset, glyph.rect, shown);
    }
    paintSettled();
  }

  void _paintGlyph(
    PaintingContext context,
    Offset offset,
    Rect rect,
    double shown,
  ) {
    void paintClipped(PaintingContext context, Offset offset) =>
        context.pushClipRect(
          needsCompositing,
          offset,
          rect,
          (context, offset) =>
              _paintFaded(context, offset, rect, shown / _fadeShare),
        );
    if (shown >= 1) {
      paintClipped(context, offset);
      return;
    }
    final rise = _rise * (1 - Curves.easeOutCubic.transform(shown));
    final scale = lerpDouble(
      _scaleFrom,
      1,
      Curves.easeOutBack.transform(shown),
    )!;
    final pivot = rect.bottomCenter;
    final transform = Matrix4.translationValues(pivot.dx, pivot.dy + rise, 0)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1);
    context.pushTransform(needsCompositing, offset, transform, paintClipped);
  }

  void _paintFaded(
    PaintingContext context,
    Offset offset,
    Rect rect,
    double opacity,
  ) {
    final child = this.child!;
    if (opacity >= 1) {
      context.paintChild(child, offset);
    } else if (needsCompositing) {
      context.pushOpacity(
        offset,
        (opacity * 255).round(),
        (context, offset) => context.paintChild(child, offset),
      );
    } else {
      context.canvas.saveLayer(
        rect.shift(offset),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
      context.paintChild(child, offset);
      context.canvas.restore();
    }
  }

  // 按阅读顺序列出每个字占的范围：横向是这个字，纵向是整行。
  List<_Glyph> _glyphs() {
    final glyphs = <_Glyph>[];
    var line = 0;
    void visit(RenderObject node) {
      if (node is! RenderParagraph) {
        node.visitChildren(visit);
        return;
      }
      final transform = node.getTransformTo(this);
      Rect place(double left, double right) => MatrixUtils.transformRect(
        transform,
        Rect.fromLTRB(left, 0, right, node.size.height),
      );
      final text = node.text.toPlainText(includeSemanticsLabels: false);
      var start = 0;
      double? end;
      for (final character in text.characters) {
        final boxes = node.getBoxesForSelection(
          TextSelection(
            baseOffset: start,
            extentOffset: start + character.length,
          ),
        );
        start += character.length;
        if (boxes.isEmpty) continue;
        final left = boxes.map((box) => box.left).reduce(math.min);
        final right = boxes.map((box) => box.right).reduce(math.max);
        glyphs.add((rect: place(left, right), line: line));
        end = right;
      }
      if (end != null && node.size.width - end > 0.5) {
        glyphs.add((rect: place(end, node.size.width), line: line));
      }
      line++;
    }

    final child = this.child;
    if (child != null) visit(child);
    return glyphs;
  }
}
