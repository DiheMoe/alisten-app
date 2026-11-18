import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:alisten/shared/theme/motion.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/physics.dart';

// 菜单像一滴液体从按钮倒出来、收回按钮：菜单主体从按钮中心一个小圆长成卡片；
// 按钮自己成为一颗水滴，沉进卡片里被吸收；两者靠近时之间长出圆润的颈。收回时
// 反过来：主体先往外一沉再缩回按钮，水滴从卡片里冒出、略冲过按钮的位置再落回，
// 最后变回按钮。

/// 主体在按钮里时的直径占按钮短边的比例。
const _bodyInButton = 0.41;

/// 水滴沉进卡片后剩下的大小，以及它沉向卡片中心走了多远。
const _dropShare = 0.25;

/// 颈能伸多远。
const _blend = 28.0;

/// 水滴沉到离卡片边缘这么深才算被吸收，卡片的描边才完整。
const _rim = 8.0;

/// 打开之初圆角比卡片圆角多出卡片宽度的这么多倍，随后收成卡片圆角。
const _cornersReach = 0.48;

/// 收回的总时长。最后 0.1 秒压住弹簧的余震，水滴正好落在按钮上。
const returnSeconds = 0.5;

/// 收回时内容在这段时间里模糊淡去。
const _contentOut = 0.1;
const _returnContentBlur = 8.0;

/// 打开时内容从这么模糊变清楚，0.07 秒左右再糊一下。
const _openContentBlur = 4.0;
const _openBlurBump = 1.9;

/// 按钮的样子在水滴里：打开时主体长到这个进度就看不见了；收回时用这么久从
/// 0.2 的不透明度变清楚。
const _glyphUnderAt = 0.25;
const _glyphIn = 0.47;

/// 收回时水滴的弹簧。
final _returnSpring = SpringSimulation(
  SpringDescription.withDampingRatio(mass: 1, stiffness: 165, ratio: 0.8),
  0,
  1,
  0,
);

/// 收回的后半程水滴被按钮吸收：颈收起，底色淡去。
const _absorbed = Interval(0.6, 0.9, curve: Curves.easeInOut);

/// 在 [peak] 秒时到 1、前后平滑为 0 的起伏，[sharpness] 越大越窄。
double riseAndFall(double time, double peak, double sharpness) {
  if (time <= 0) return 0;
  final x = time / peak;
  return math.pow(x, sharpness) * math.exp(sharpness * (1 - x)).toDouble();
}

/// 菜单此刻在倒出还是在收回。
sealed class Pour {
  const Pour();

  /// 内容有多清楚。
  double get reveal;

  /// 内容的模糊半径。
  double get contentBlur;
}

/// 从按钮倒出：[progress] 是打开弹簧的进度，会冲过 1；[time] 是打开后的秒数；
/// [squared] 从 0 到 1，圆角从胶囊收成卡片。
@immutable
final class PourOut extends Pour {
  const PourOut({
    required this.progress,
    required this.time,
    required this.squared,
  });

  final double progress;
  final double time;
  final double squared;

  double get settled => progress.clamp(0.0, 1.0);

  @override
  double get reveal => settled;

  @override
  double get contentBlur {
    final fading = _openContentBlur * (1 - settled);
    final bump = _openBlurBump * riseAndFall(time, 0.069, 2.1);
    return math.sqrt(fading * fading + bump * bump);
  }

  @override
  bool operator ==(Object other) =>
      other is PourOut &&
      other.progress == progress &&
      other.time == time &&
      other.squared == squared;

  @override
  int get hashCode => Object.hash(progress, time, squared);
}

/// 收回按钮，[time] 是开始收回后的秒数；[from] 是还没开完就收回时停在的
/// 那一刻，为 null 时从完整的卡片收回。
@immutable
final class PourBack extends Pour {
  const PourBack({required this.time, this.from});

  final double time;
  final PourOut? from;

  @override
  double get reveal =>
      (from?.reveal ?? 1) *
      (1 - Curves.easeOut.transform((time / _contentOut).clamp(0.0, 1.0)));

  @override
  double get contentBlur => _returnContentBlur * (1 - reveal);

  @override
  bool operator ==(Object other) =>
      other is PourBack && other.time == time && other.from == from;

  @override
  int get hashCode => Object.hash(time, from);
}

/// 一帧液滴：菜单主体和按钮变成的水滴，以及各部分此刻有多实。
@immutable
class DropFrame {
  const DropFrame({
    required this.body,
    required this.bodyRadius,
    required this.drop,
    required this.blend,
    required this.solid,
    required this.lift,
    required this.rim,
    required this.glyph,
    required this.glyphBlur,
  });

  final Rect body;
  final double bodyRadius;
  final Rect drop;

  /// 颈能伸多远，为 0 时两者只是叠在一起。
  final double blend;

  /// 底色、阴影、描边和按钮样子的不透明度系数。
  final double solid;
  final double lift;
  final double rim;
  final double glyph;
  final double glyphBlur;

  RRect get bodyShape =>
      RRect.fromRectAndRadius(body, Radius.circular(bodyRadius));

  RRect get dropShape =>
      RRect.fromRectAndRadius(drop, Radius.circular(drop.shortestSide / 2));
}

/// [anchor] 是按钮，[card] 是菜单停稳时的卡片，[cardRadius] 是卡片圆角，
/// 都在同一个坐标系里。
DropFrame dropFrameOf(
  Pour pour, {
  required Rect anchor,
  required Rect card,
  required double cardRadius,
}) => switch (pour) {
  PourOut() => _out(pour, anchor, card, cardRadius),
  PourBack() => _back(pour, anchor, card, cardRadius),
};

/// 长条按钮比圆形多出的长度：主体在按钮里时保留它，胶囊按钮收进的也是胶囊。
Size _beyondRound(Rect anchor) => Size(
  math.max(0.0, anchor.width - anchor.height),
  math.max(0.0, anchor.height - anchor.width),
);

DropFrame _out(PourOut pour, Rect anchor, Rect card, double cardRadius) {
  final progress = pour.progress;
  final settled = pour.settled;
  final scale = ui.lerpDouble(
    _bodyInButton * anchor.shortestSide / card.width,
    1,
    progress,
  )!;
  // 起初是圆，长高成卡片。
  final tall = ui.lerpDouble(card.width, card.height, progress)!;
  final beyond = _beyondRound(anchor) * (1 - settled);
  final toCard = card.center.dy - anchor.center.dy;
  final distance = toCard.abs();
  // 主体先冲过卡片的位置再回来，像被倒出来。
  final dip =
      toCard.sign *
      (math.min(1.0, distance / 30) * 23 + 0.124 * distance) *
      riseAndFall(pour.time, 0.098, 3.3);
  final body = Rect.fromCenter(
    center: Offset.lerp(anchor.center, card.center, progress)! + Offset(0, dip),
    width: math.max(0.0, card.width * scale + beyond.width),
    height: math.max(0.0, tall * scale + beyond.height),
  );
  final corners = cardRadius + card.width * _cornersReach * (1 - pour.squared);
  final bodyRadius = math.max(0.0, math.min(tall / 2, corners) * scale);

  final extent = anchor.size * ui.lerpDouble(1, _dropShare, progress)!;
  final inner = card.deflate(
    anchor.longestSide * _dropShare / 2 + _blend + _rim,
  );
  final sunk = Offset.lerp(anchor.center, card.center, _dropShare)!;
  final target = inner.isEmpty
      ? card.center
      : Offset(
          sunk.dx.clamp(inner.left, inner.right),
          sunk.dy.clamp(inner.top, inner.bottom),
        );
  final drop = Rect.fromCenter(
    center: Offset.lerp(anchor.center, target, progress)!,
    width: extent.width,
    height: extent.height,
  );
  final under = math.min(1.0, settled / _glyphUnderAt);
  return DropFrame(
    body: body,
    bodyRadius: bodyRadius,
    drop: drop,
    blend: _blend,
    solid: morphSolid(progress),
    lift: settled * settled,
    rim: settled * (_depth(body, bodyRadius, drop) / _rim).clamp(0.0, 1.0),
    glyph: 1 - under,
    glyphBlur: _openContentBlur * under,
  );
}

DropFrame _back(PourBack pour, Rect anchor, Rect card, double cardRadius) {
  final time = pour.time;
  final opened = pour.from == null
      ? null
      : _out(pour.from!, anchor, card, cardRadius);
  final from = opened?.body ?? card;
  final fromRadius = opened?.bodyRadius ?? cardRadius;
  final fromDrop =
      opened?.drop ??
      Rect.fromCenter(
        center: Offset.lerp(anchor.center, from.center, _dropShare)!,
        width: anchor.width * _dropShare,
        height: anchor.height * _dropShare,
      );
  // 弹簧到时还在轻轻晃；最后 0.1 秒把它压住，水滴正好落在按钮上。
  final ringing =
      1 - Curves.easeIn.transform(((time - 0.4) / 0.1).clamp(0.0, 1.0));
  final progress = 1 + (_returnSpring.x(time) - 1) * ringing;
  final toCard = from.center.dy - anchor.center.dy;
  final away = toCard.sign;
  // 主体先往远离按钮的方向一沉；水滴冲过按钮的位置再落回。
  final dip =
      math.min(0.21 * toCard.abs(), 22.0) * riseAndFall(time, 0.072, 2.4);
  final lift =
      math.min(0.25 * toCard.abs(), 19.0) * riseAndFall(time, 0.176, 4.9);
  final scale = ui.lerpDouble(
    1,
    _bodyInButton * anchor.shortestSide / math.max(from.width, from.height),
    progress,
  )!;
  final beyond = _beyondRound(anchor) * progress.clamp(0.0, 1.0);
  final body = Rect.fromCenter(
    center:
        Offset.lerp(from.center, anchor.center, progress)! +
        Offset(0, away * dip * ringing),
    width: math.max(0.0, from.width * scale + beyond.width),
    height: math.max(
      0.0,
      ui.lerpDouble(from.height, from.width, progress)! * scale + beyond.height,
    ),
  );
  final bodyRadius = math.max(
    0.0,
    ui.lerpDouble(fromRadius, from.width / 2, progress)! * scale,
  );
  final drop = Rect.fromCenter(
    center:
        Offset.lerp(fromDrop.center, anchor.center, progress)! -
        Offset(0, away * lift * ringing),
    width: ui.lerpDouble(fromDrop.width, anchor.width, progress)!,
    height: ui.lerpDouble(fromDrop.height, anchor.height, progress)!,
  );
  final absorbed = _absorbed.transform((time / returnSeconds).clamp(0.0, 1.0));
  final remaining = (1 - progress).clamp(0.0, 1.0);
  return DropFrame(
    body: body,
    bodyRadius: bodyRadius,
    drop: drop,
    blend: _blend * math.min(1.0, time / 0.05) * (1 - absorbed),
    solid: math.min(opened?.solid ?? 1, 1 - absorbed),
    lift: remaining * remaining,
    rim: remaining * (_depth(body, bodyRadius, drop) / _rim).clamp(0.0, 1.0),
    glyph: ui.lerpDouble(
      0.2,
      1,
      Curves.ease.transform((time / _glyphIn).clamp(0.0, 1.0)),
    )!,
    glyphBlur: 0,
  );
}

/// 水滴整个沉进主体后，离颈不再鼓出来还有多深；还连着颈时为负。
double _depth(Rect body, double radius, Rect drop) {
  final outermost = [
    drop.topLeft,
    drop.topRight,
    drop.bottomLeft,
    drop.bottomRight,
  ].map((corner) => _roundedDistance(body, radius, corner)).reduce(math.max);
  return -outermost - _blend;
}

double _roundedDistance(Rect rect, double radius, Offset point) {
  final round = math.min(radius, rect.shortestSide / 2);
  final qx = (point.dx - rect.center.dx).abs() - rect.width / 2 + round;
  final qy = (point.dy - rect.center.dy).abs() - rect.height / 2 + round;
  return Offset(math.max(qx, 0), math.max(qy, 0)).distance +
      math.min(math.max(qx, qy), 0) -
      round;
}

/// 画液滴底色的着色器，第一次用到前加载；没加载好时两块各画各的，没有颈。
abstract final class Goo {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  static ui.FragmentProgram? get program => _program;

  static void load() {
    _loading ??= ui.FragmentProgram.fromAsset('shaders/goo.frag').then(
      (program) => _program = program,
      onError: (Object exception, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: exception,
            stack: stack,
            library: 'alisten',
            context: ErrorDescription('while loading the drop shader'),
          ),
        );
      },
    );
  }
}

/// 用 [shader] 把 [frame] 的主体和水滴画成一体；[pixel] 是一个物理像素有
/// 多少本地单位。
void paintGoo(
  Canvas canvas,
  DropFrame frame,
  Color color, {
  required ui.FragmentShader? shader,
  required double pixel,
}) {
  if (color.a <= 0) return;
  if (shader == null) {
    canvas.drawPath(
      Path.combine(
        PathOperation.union,
        Path()..addRRect(frame.bodyShape),
        Path()..addRRect(frame.dropShape),
      ),
      Paint()..color = color,
    );
    return;
  }
  final body = frame.body;
  final drop = frame.drop;
  final values = [
    body.center.dx,
    body.center.dy,
    body.width / 2,
    body.height / 2,
    frame.bodyRadius,
    drop.center.dx,
    drop.center.dy,
    drop.width / 2,
    drop.height / 2,
    frame.blend,
    pixel,
    color.r * color.a,
    color.g * color.a,
    color.b * color.a,
    color.a,
  ];
  for (var i = 0; i < values.length; i++) {
    shader.setFloat(i, values[i]);
  }
  canvas.drawRect(
    body.expandToInclude(drop).inflate(frame.blend + pixel * 2),
    Paint()..shader = shader,
  );
}

/// 按钮的样子画在水滴里。
void paintGlyph(Canvas canvas, ui.Image image, DropFrame frame) {
  final opacity = frame.glyph;
  if (opacity <= 0) return;
  final blur = frame.glyphBlur;
  canvas.drawImageRect(
    image,
    Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
    frame.drop,
    Paint()
      ..color = Color.fromRGBO(0, 0, 0, opacity)
      ..filterQuality = FilterQuality.medium
      ..imageFilter = blur > 0.1
          ? ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur)
          : null,
  );
}
