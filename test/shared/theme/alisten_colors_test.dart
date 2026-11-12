import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text on the brand fill reaches 4.5:1 whatever the cover', () {
    double contrast(Color a, Color b) {
      final (light, dark) = (a.computeLuminance(), b.computeLuminance());
      return light > dark
          ? (light + 0.05) / (dark + 0.05)
          : (dark + 0.05) / (light + 0.05);
    }

    final seeds = [
      for (var hue = 0.0; hue < 360; hue += 20)
        HSLColor.fromAHSL(1, hue, 0.85, 0.55).toColor(),
      // 浅色主题下文字对比度容易不足的封面色。
      const Color(0xFFB5E61D),
      const Color(0xFFFFD60A),
      const Color(0xFF2BD08F),
      const Color(0xFF808080),
    ];
    for (final seed in seeds) {
      for (final brightness in Brightness.values) {
        final colors = AlistenColors.fromScheme(
          ColorScheme.fromSeed(
            seedColor: seed,
            brightness: brightness,
            dynamicSchemeVariant: AlistenColors.schemeVariant,
          ),
        );
        expect(
          contrast(colors.onBrand, colors.brand),
          greaterThanOrEqualTo(4.5),
          reason: '$seed $brightness ${colors.brand}',
        );
      }
    }
  });

  test('in the room, text and the play controls stay legible over the '
      'thinnest part of the cover backdrop', () {
    double contrast(Color a, Color b) {
      final (light, dark) = (a.computeLuminance(), b.computeLuminance());
      return light > dark
          ? (light + 0.05) / (dark + 0.05)
          : (dark + 0.05) / (light + 0.05);
    }

    for (var hue = 0.0; hue < 360; hue += 30) {
      for (final brightness in Brightness.values) {
        final scheme = ColorScheme.fromSeed(
          seedColor: HSLColor.fromAHSL(1, hue, 0.85, 0.55).toColor(),
          brightness: brightness,
          dynamicSchemeVariant: AlistenColors.schemeVariant,
        );
        final colors = AlistenColors.fromScheme(scheme, immersive: true);
        // 遮罩最薄处压在对文字最不利的封面颜色上：深色房间是封面最亮的颜色，
        // 浅色房间是近于黑的阴影。
        final thinnest = colors.scrim.colors.reduce(
          (a, b) => a.a < b.a ? a : b,
        );
        final worstCover = brightness == Brightness.dark
            ? colors.glow
            : const Color(0xFF101010);
        final backdrop = Color.alphaBlend(thinnest, worstCover);
        final panel = Color.alphaBlend(colors.glassFill, backdrop);
        for (final (name, ink, background) in [
          ('onGlass on the backdrop', colors.onGlass, backdrop),
          ('onGlass on a panel', colors.onGlass, panel),
          (
            'onGlassMuted on a panel',
            Color.alphaBlend(colors.onGlassMuted, panel),
            panel,
          ),
          ('onControl on control', colors.onControl, colors.control),
        ]) {
          expect(
            contrast(ink, background),
            greaterThanOrEqualTo(4.5),
            reason: '$hue $brightness $name',
          );
        }
      }
    }
  });

  test('control outlines stand out 3:1 from the page, panels and sheets', () {
    double contrast(Color a, Color b) {
      final (light, dark) = (a.computeLuminance(), b.computeLuminance());
      return light > dark
          ? (light + 0.05) / (dark + 0.05)
          : (dark + 0.05) / (light + 0.05);
    }

    for (var hue = 0.0; hue < 360; hue += 30) {
      for (final brightness in Brightness.values) {
        final scheme = ColorScheme.fromSeed(
          seedColor: HSLColor.fromAHSL(1, hue, 0.85, 0.55).toColor(),
          brightness: brightness,
          dynamicSchemeVariant: AlistenColors.schemeVariant,
        );
        final colors = AlistenColors.fromScheme(scheme);
        for (final background in [
          scheme.surface,
          Color.alphaBlend(colors.glassFill, scheme.surface),
          colors.raised,
        ]) {
          expect(
            contrast(Color.alphaBlend(colors.outline, background), background),
            greaterThanOrEqualTo(3),
            reason: '$hue $brightness $background',
          );
        }
      }
    }
  });

  test('a glowing line of text has a wide halo of the cover and a tight core, '
      'white on dark themes and of the cover on light ones', () {
    for (final brightness in Brightness.values) {
      final colors = AlistenColors.brandScheme(brightness);
      final glowing = AlistenColors.fromScheme(colors);
      final [halo, core] = glowing.glowTextShadows;

      expect(halo.color.withValues(alpha: 1), glowing.glow);
      expect(
        core.color.withValues(alpha: 1),
        brightness == Brightness.dark ? Colors.white : glowing.glow,
        reason: '$brightness',
      );
      expect(halo.color.a, greaterThan(0.5));
      expect(core.color.a, greaterThan(0));
      expect(halo.blurRadius, greaterThan(core.blurRadius));
    }
  });

  test('the glow of text moves with the other colours of a theme', () {
    final light = AlistenColors.fromScheme(
      AlistenColors.brandScheme(Brightness.light),
    );
    final dark = AlistenColors.fromScheme(
      AlistenColors.brandScheme(Brightness.dark),
    );

    expect(light.glowTextShadows, isNot(dark.glowTextShadows));
    expect(light.lerp(dark, 0).glowTextShadows, light.glowTextShadows);
    expect(light.lerp(dark, 1).glowTextShadows, dark.glowTextShadows);
    final middle = light.lerp(dark, 0.5).glowTextShadows;
    for (var shadow = 0; shadow < 2; shadow++) {
      final ends = (
        light.glowTextShadows[shadow].color,
        dark.glowTextShadows[shadow].color,
      );
      expect(ends.$1, isNot(ends.$2), reason: 'shadow $shadow');
      expect(
        middle[shadow].color,
        Color.lerp(ends.$1, ends.$2, 0.5),
        reason: 'shadow $shadow',
      );
    }
    expect(light.copyWith(glowTextShadows: const []).glowTextShadows, isEmpty);
    expect(light.copyWith(), light);
    expect(light.copyWith(glowTextShadows: const []), isNot(light));
  });
}
