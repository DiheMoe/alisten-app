import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/material.dart';

/// 框架组件不显示水波纹，按压反馈由各组件自行绘制。[immersive] 见
/// [AlistenColors.fromScheme]。
ThemeData buildAlistenTheme(ColorScheme scheme, {bool immersive = false}) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AlistenTypography.family,
    fontFamilyFallback: AlistenTypography.fallback,
    textTheme: _textTheme(),
    // 框架在桌面系统上默认用紧凑密度，会把输入框上下的内边距各减 4。组件的
    // 尺寸都是自己定的，不随平台变。
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.3),
      selectionHandleColor: scheme.primary,
    ),
    extensions: [AlistenColors.fromScheme(scheme, immersive: immersive)],
  );
}

TextTheme _textTheme() => TextTheme(
  displayLarge: AlistenTypography.largeTitle,
  displayMedium: AlistenTypography.largeTitle,
  displaySmall: AlistenTypography.largeTitle,
  headlineLarge: AlistenTypography.largeTitle,
  headlineMedium: AlistenTypography.largeTitle,
  headlineSmall: AlistenTypography.title,
  titleLarge: AlistenTypography.title,
  titleMedium: AlistenTypography.bodyStrong,
  titleSmall: AlistenTypography.weighted(
    AlistenTypography.secondary,
    FontWeight.w600,
  ),
  bodyLarge: AlistenTypography.body,
  bodyMedium: AlistenTypography.body,
  bodySmall: AlistenTypography.secondary,
  labelLarge: AlistenTypography.bodyStrong,
  labelMedium: AlistenTypography.weighted(
    AlistenTypography.secondary,
    FontWeight.w600,
  ),
  labelSmall: AlistenTypography.caption,
);
