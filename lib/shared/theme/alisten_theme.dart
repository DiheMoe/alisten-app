import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 框架组件不显示水波纹，按压反馈由各组件自行绘制。
ThemeData buildAlistenTheme(ColorScheme scheme) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AlistenTypography.family,
    textTheme: _textTheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: AlistenPageTransitionsBuilder(),
        TargetPlatform.iOS: AlistenCupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: AlistenCupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: AlistenPageTransitionsBuilder(),
        TargetPlatform.windows: AlistenPageTransitionsBuilder(),
        TargetPlatform.fuchsia: AlistenPageTransitionsBuilder(),
      },
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.3),
      selectionHandleColor: scheme.primary,
    ),
    extensions: [AlistenColors.fromScheme(scheme)],
  );
}

final _textTheme = TextTheme(
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

final class AlistenPageTransitionsBuilder extends PageTransitionsBuilder {
  const AlistenPageTransitionsBuilder();

  static final _opacity = CurveTween(curve: AlistenCurves.standard);
  static final _rise = Tween(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).chain(CurveTween(curve: AlistenCurves.standard));

  @override
  Duration get transitionDuration => AlistenDurations.medium;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return FadeTransition(
      opacity: animation.drive(_opacity),
      child: SlideTransition(position: animation.drive(_rise), child: child),
    );
  }
}

/// Apple 平台沿用系统转场，因为只有它支持边缘滑动返回。系统要求减少动态效果
/// 时，页面立即出现和离开，滑动返回仍跟随手指。
final class AlistenCupertinoPageTransitionsBuilder
    extends PageTransitionsBuilder {
  const AlistenCupertinoPageTransitionsBuilder();

  static const _system = CupertinoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _system.transitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _delegatedTransition;

  static Widget? _delegatedTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return _system.delegatedTransition?.call(
      context,
      animation,
      secondaryAnimation,
      allowSnapshotting,
      child,
    );
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final instant =
        MediaQuery.disableAnimationsOf(context) && !route.popGestureInProgress;
    return _system.buildTransitions(
      route,
      context,
      instant ? kAlwaysCompleteAnimation : animation,
      instant ? kAlwaysDismissedAnimation : secondaryAnimation,
      child,
    );
  }
}
