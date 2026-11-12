import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

@immutable
final class AlistenColors extends ThemeExtension<AlistenColors> {
  const AlistenColors({
    required this.brand,
    required this.onBrand,
    required this.glow,
    required this.glowTextShadows,
    required this.coverShadow,
    required this.control,
    required this.onControl,
    required this.aurora,
    required this.scrim,
    required this.glassFill,
    required this.glassStroke,
    required this.selectedFill,
    required this.bubble,
    required this.onGlass,
    required this.onGlassMuted,
    required this.raised,
    required this.floor,
    required this.outline,
    required this.knob,
    required this.barrier,
    required this.success,
    required this.warning,
    required this.danger,
  });

  /// [immersive] 用于房间：颜色取自封面，流动背景是房间的主角。深色时压暗，
  /// 浅色时用白色冲淡成干净的浅色，文字和控件靠不透明度分层。房间外的页面保持
  /// 安静的中性底色。
  factory AlistenColors.fromScheme(
    ColorScheme scheme, {
    bool immersive = false,
  }) {
    final dark = scheme.brightness == Brightness.dark;
    // 饱和但不到荧光色：荧光色大面积填充时刺眼。
    final fill = _saturated(
      scheme.primary,
      lightness: dark ? 0.72 : 0.44,
      minSaturation: 0.7,
      maxSaturation: 0.9,
    );
    final underWhite = _legibleUnder(Colors.white, fill, fill);
    // onPrimaryFixed 是主色色相中最深的色调。
    final underDeep = _legibleUnder(scheme.onPrimaryFixed, fill, fill);
    // 浅色主题在深色填充上用白字，深色主题在浅色填充上用深色字；若因此要让
    // 填充明显偏离原来的颜色，就改用另一种，黄、绿封面因而保持明亮并配深色字。
    final (usual, other) = dark
        ? (underDeep, underWhite)
        : (underWhite, underDeep);
    // 没有色相的配色（界面自己的黑白灰）不能硬提饱和度，否则灰会变成红。
    final colorless = HSLColor.fromColor(scheme.primary).saturation < 0.05;
    final brand = colorless
        ? (
            start: scheme.onSurface,
            end: scheme.onSurface,
            ink: scheme.surface,
            shift: 0.0,
          )
        : usual.shift <= _tolerableShift || usual.shift <= other.shift
        ? usual
        : other;
    Color vivid(Color color) => colorless
        ? HSLColor.fromColor(color).withLightness(dark ? 0.6 : 0.56).toColor()
        : _saturated(
            color,
            lightness: dark ? 0.6 : 0.56,
            minSaturation: 0.62,
          ).toColor();
    final surface = scheme.surface;
    final glow = vivid(scheme.primary);
    final lightRoom = immersive && !dark;
    // 房间的流动封面在深色时要压得够暗，白字和歌词才有对比；浅色时用纯白而不是
    // 带色调的底色去冲淡，带色调的底色盖在饱和的封面上会发灰。
    final scrimBase = lightRoom ? Colors.white : surface;
    final scrimAlphas = switch ((immersive, dark)) {
      (true, true) => const [0.68, 0.66, 0.84],
      (true, false) => const [0.68, 0.6, 0.82],
      (false, true) => const [0.4, 0.22, 0.6],
      (false, false) => const [0.55, 0.42, 0.74],
    };
    return AlistenColors(
      brand: brand.start,
      onBrand: brand.ink,
      glow: glow,
      glowTextShadows: List.unmodifiable([
        Shadow(color: glow.withValues(alpha: 0.85), blurRadius: 26),
        // 深色主题用白色内芯；浅色主题上白色会看不见。
        Shadow(
          color: (dark ? Colors.white : glow).withValues(alpha: 0.35),
          blurRadius: 8,
        ),
      ]),
      coverShadow: List.unmodifiable([
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.42 : 0.16),
          blurRadius: 40,
          offset: const Offset(0, 16),
        ),
      ]),
      // 浅色房间里播放键和进度条用封面色；文字色在浅色下近于黑，填满一个圆显得
      // 生硬。
      control: lightRoom ? brand.start : scheme.onSurface,
      onControl: lightRoom ? brand.ink : surface,
      // 深色房间没有封面时，极光是深色底上的一抹颜色，不能亮到压过白字。
      aurora: List.unmodifiable([
        for (final color in [scheme.primary, scheme.tertiary, scheme.secondary])
          immersive && dark && !colorless
              ? _saturated(
                  color,
                  lightness: 0.42,
                  minSaturation: 0.62,
                ).toColor()
              : immersive && dark
              ? HSLColor.fromColor(color).withLightness(0.3).toColor()
              : vivid(color),
      ]),
      scrim: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, 0.45, 1],
        colors: [
          for (final alpha in scrimAlphas) scrimBase.withValues(alpha: alpha),
        ],
      ),
      // 深色房间里的面板是压在流动封面上的一层暗玻璃，不是提亮背景的白雾。
      glassFill: immersive && dark
          ? Colors.black.withValues(alpha: 0.3)
          : Colors.white.withValues(alpha: dark ? 0.075 : 0.62),
      glassStroke: dark
          ? Colors.white.withValues(alpha: 0.1)
          : scheme.onSurface.withValues(alpha: 0.07),
      selectedFill: scheme.onSurface.withValues(alpha: 0.2),
      bubble: Colors.white.withValues(alpha: dark ? 0.12 : 0.86),
      onGlass: scheme.onSurface,
      // 极光最亮处叠上玻璃面板时，不透明度再低，辅助文字就达不到 4.5:1。
      onGlassMuted: scheme.onSurface.withValues(
        alpha: immersive && dark ? 0.8 : 0.72,
      ),
      raised: dark
          ? Color.alphaBlend(
              Colors.white.withValues(alpha: 0.06),
              scheme.surfaceContainerHigh,
            )
          : Colors.white,
      floor: scheme.surface.withValues(alpha: 0.94),
      outline: scheme.onSurface.withValues(alpha: dark ? 0.48 : 0.52),
      knob: Colors.white,
      barrier: scheme.scrim.withValues(alpha: dark ? 0.55 : 0.4),
      // 色相固定，状态在任何封面上看起来都一样。每种颜色在底色、玻璃面板和
      // 用它着色的胶囊上都达到 4.5:1 的对比度。
      success: dark ? const Color(0xFF6FD99B) : const Color(0xFF136B41),
      warning: dark ? const Color(0xFFF2B44A) : const Color(0xFF835100),
      danger: scheme.error,
    );
  }

  /// 非 `buildAlistenTheme` 构建的主题（如测试中的裸主题）没有这个扩展，颜色
  /// 改由其配色方案推导。
  static AlistenColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AlistenColors>() ??
        (_derived[theme.colorScheme] ??= AlistenColors.fromScheme(
          theme.colorScheme,
        ));
  }

  static final _derived = Expando<AlistenColors>();

  /// 无图片对象（如没有头像的成员、房间）的填充和文字色。同一 [seed] 在深浅主题
  /// 下颜色相同，文字与填充的对比度不低于 4.5:1。饱和度有意压低，许多头像排在
  /// 一起时不抢内容。
  static ({Color fill, Color ink}) identity(String seed) {
    // 用 FNV-1a 计算，使色相在不同运行和平台之间保持不变。
    var hash = 0x811C9DC5;
    for (final unit in seed.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    final hue = (hash % 360).toDouble();
    final tone = HSLColor.fromAHSL(1, hue, 0.38, 0.5);
    final legible = _legibleUnder(Colors.white, tone, tone);
    return (fill: legible.start, ink: legible.ink);
  }

  /// 鲜艳变体的主色保持来源的色相。
  static const schemeVariant = DynamicSchemeVariant.vibrant;

  /// 不随主题和封面变化：扫码依赖浅底深色模块，透明底的二维码放在深色面板上
  /// 可能扫不出来。
  static const scanSurface = Color(0xFFFFFFFF);
  static const scanInk = Color(0x8A000000);

  /// 界面自己不带颜色：黑白灰，与黑底的应用图标一致。颜色只来自封面。
  static ColorScheme brandScheme(Brightness brightness) {
    return ColorScheme.fromSeed(
      seedColor: const Color(0xFF808080),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
    );
  }

  /// 主要按钮、开关、自己的消息等唯一的强调填充。房间里取自封面，房间外是文字色。
  final Color brand;

  /// 与 [brand] 的对比度不低于 4.5:1。
  final Color onBrand;

  /// 只用于随音乐变化的光：歌词长音、进度端点。
  final Color glow;
  final List<Shadow> glowTextShadows;

  /// 封面这类实物图片下的阴影，不带颜色。
  final List<BoxShadow> coverShadow;

  /// 播放键、进度条已播放部分这类跟随音乐的主控件。
  final Color control;

  /// 与 [control] 的对比度不低于 4.5:1。
  final Color onControl;

  /// 固定三种颜色。
  final List<Color> aurora;
  final LinearGradient scrim;
  final Color glassFill;
  final Color glassStroke;

  /// 用文字色调出深浅才能在玻璃上分辨，再叠一层玻璃填充几乎看不出。
  final Color selectedFill;

  /// 比 [glassFill] 更不透明，短消息在背景上也能看出形状。
  final Color bubble;
  final Color onGlass;
  final Color onGlassMuted;
  final Color raised;
  final Color floor;

  /// 关闭或空的控件部分的填充（如关闭的开关、进度条未播放部分），与页面、玻璃
  /// 面板和面板的对比度达到 3:1，控件才能辨认。
  final Color outline;
  final Color knob;
  final Color barrier;
  final Color success;

  /// 进行中或结果不确定的状态，例如重连中。
  final Color warning;
  final Color danger;

  @override
  AlistenColors copyWith({
    Color? brand,
    Color? onBrand,
    Color? glow,
    List<Shadow>? glowTextShadows,
    List<BoxShadow>? coverShadow,
    Color? control,
    Color? onControl,
    List<Color>? aurora,
    LinearGradient? scrim,
    Color? glassFill,
    Color? glassStroke,
    Color? selectedFill,
    Color? bubble,
    Color? onGlass,
    Color? onGlassMuted,
    Color? raised,
    Color? floor,
    Color? outline,
    Color? knob,
    Color? barrier,
    Color? success,
    Color? warning,
    Color? danger,
  }) {
    return AlistenColors(
      brand: brand ?? this.brand,
      onBrand: onBrand ?? this.onBrand,
      glow: glow ?? this.glow,
      glowTextShadows: glowTextShadows ?? this.glowTextShadows,
      coverShadow: coverShadow ?? this.coverShadow,
      control: control ?? this.control,
      onControl: onControl ?? this.onControl,
      aurora: aurora ?? this.aurora,
      scrim: scrim ?? this.scrim,
      glassFill: glassFill ?? this.glassFill,
      glassStroke: glassStroke ?? this.glassStroke,
      selectedFill: selectedFill ?? this.selectedFill,
      bubble: bubble ?? this.bubble,
      onGlass: onGlass ?? this.onGlass,
      onGlassMuted: onGlassMuted ?? this.onGlassMuted,
      raised: raised ?? this.raised,
      floor: floor ?? this.floor,
      outline: outline ?? this.outline,
      knob: knob ?? this.knob,
      barrier: barrier ?? this.barrier,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  AlistenColors lerp(AlistenColors? other, double t) {
    if (other == null) return this;
    return AlistenColors(
      brand: Color.lerp(brand, other.brand, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      glowTextShadows: List.unmodifiable(
        Shadow.lerpList(glowTextShadows, other.glowTextShadows, t)!,
      ),
      coverShadow: List.unmodifiable(
        BoxShadow.lerpList(coverShadow, other.coverShadow, t)!,
      ),
      control: Color.lerp(control, other.control, t)!,
      onControl: Color.lerp(onControl, other.onControl, t)!,
      aurora: List.unmodifiable([
        for (var index = 0; index < aurora.length; index++)
          Color.lerp(aurora[index], other.aurora[index], t)!,
      ]),
      scrim: LinearGradient.lerp(scrim, other.scrim, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassStroke: Color.lerp(glassStroke, other.glassStroke, t)!,
      selectedFill: Color.lerp(selectedFill, other.selectedFill, t)!,
      bubble: Color.lerp(bubble, other.bubble, t)!,
      onGlass: Color.lerp(onGlass, other.onGlass, t)!,
      onGlassMuted: Color.lerp(onGlassMuted, other.onGlassMuted, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      floor: Color.lerp(floor, other.floor, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      knob: Color.lerp(knob, other.knob, t)!,
      barrier: Color.lerp(barrier, other.barrier, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }

  // 颜色相同即视为同一主题，同一封面重建主题时不触发颜色动画。
  @override
  bool operator ==(Object other) {
    return other is AlistenColors &&
        other.brand == brand &&
        other.onBrand == onBrand &&
        other.glow == glow &&
        listEquals(other.glowTextShadows, glowTextShadows) &&
        listEquals(other.coverShadow, coverShadow) &&
        other.control == control &&
        other.onControl == onControl &&
        listEquals(other.aurora, aurora) &&
        other.scrim == scrim &&
        other.glassFill == glassFill &&
        other.glassStroke == glassStroke &&
        other.selectedFill == selectedFill &&
        other.bubble == bubble &&
        other.onGlass == onGlass &&
        other.onGlassMuted == onGlassMuted &&
        other.raised == raised &&
        other.floor == floor &&
        other.outline == outline &&
        other.knob == knob &&
        other.barrier == barrier &&
        other.success == success &&
        other.warning == warning &&
        other.danger == danger;
  }

  @override
  int get hashCode => Object.hashAll([
    brand,
    onBrand,
    glow,
    Object.hashAll(glowTextShadows),
    Object.hashAll(coverShadow),
    control,
    onControl,
    Object.hashAll(aurora),
    scrim,
    glassFill,
    glassStroke,
    selectedFill,
    bubble,
    onGlass,
    onGlassMuted,
    raised,
    floor,
    outline,
    knob,
    barrier,
    success,
    warning,
    danger,
  ]);
}

const _minimumContrast = 4.5;

/// 为常规文字色调整品牌渐变时，HSL 亮度可偏离封面颜色的上限；超过上限且另一种
/// 文字色偏离更小时，改用另一种。
const _tolerableShift = 0.12;

HSLColor _saturated(
  Color color, {
  required double lightness,
  required double minSaturation,
  double maxSaturation = 1,
}) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withSaturation(clampDouble(hsl.saturation, minSaturation, maxSaturation))
      .withLightness(lightness);
}

typedef _Legible = ({Color start, Color end, Color ink, double shift});

/// 把渐变两端的亮度逐步推离 [ink]，直到 [ink] 在渐变上均匀取的九个点都达到最低
/// 对比度；`shift` 是两端中较大的亮度变化。
_Legible _legibleUnder(Color ink, HSLColor start, HSLColor end) {
  final lighten = ink.computeLuminance() < 0.5;
  final (fromStart, fromEnd) = (start.lightness, end.lightness);
  bool readable(Color background) =>
      _contrast(ink, background) >= _minimumContrast;
  HSLColor nudge(HSLColor color) => color.withLightness(
    clampDouble(color.lightness + (lighten ? 0.01 : -0.01), 0, 1),
  );
  // 两端推到纯白或纯黑时一定可读，所以 100 步之内必定结束。
  for (var step = 0; step <= 100; step++) {
    final (from, to) = (start.toColor(), end.toColor());
    final between = [
      for (var point = 1; point < 8; point++) Color.lerp(from, to, point / 8)!,
    ].every(readable);
    if (readable(from) && readable(to) && between) break;
    if (!readable(from) || !between) start = nudge(start);
    if (!readable(to) || !between) end = nudge(end);
  }
  return (
    start: start.toColor(),
    end: end.toColor(),
    ink: ink,
    shift: math.max(
      (start.lightness - fromStart).abs(),
      (end.lightness - fromEnd).abs(),
    ),
  );
}

double _contrast(Color a, Color b) {
  final (first, second) = (a.computeLuminance(), b.computeLuminance());
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}
