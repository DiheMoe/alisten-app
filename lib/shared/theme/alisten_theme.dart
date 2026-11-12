import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 框架组件不显示水波纹，按压反馈由各组件自行绘制。[immersive] 见
/// [AlistenColors.fromScheme]。
ThemeData buildAlistenTheme(ColorScheme scheme, {bool immersive = false}) {
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
    extensions: [AlistenColors.fromScheme(scheme, immersive: immersive)],
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

/// 新页面从右侧推入，底下的页面退向左侧并变暗。`fullscreenDialog` 路由是从当前
/// 页面临时打开的任务，从底部升起，底下的页面留在原地。
final class AlistenPageTransitionsBuilder extends PageTransitionsBuilder {
  const AlistenPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AlistenDurations.pageEnter;

  @override
  Duration get reverseTransitionDuration => AlistenDurations.pageExit;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return _PageMotion(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      rises: route.fullscreenDialog,
      child: child,
    );
  }
}

class _PageMotion extends StatefulWidget {
  const _PageMotion({
    required this.animation,
    required this.secondaryAnimation,
    required this.rises,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final bool rises;
  final Widget child;

  @override
  State<_PageMotion> createState() => _PageMotionState();
}

class _PageMotionState extends State<_PageMotion> {
  static final _fromRight = Tween(begin: const Offset(1, 0), end: Offset.zero);
  static final _fromBottom = Tween(begin: const Offset(0, 1), end: Offset.zero);
  static final _receded = Tween(
    begin: Offset.zero,
    end: const Offset(-0.25, 0),
  );
  static final _dimmed = Tween<double>(begin: 0, end: 0.18);

  late CurvedAnimation _entering;
  late CurvedAnimation _covered;

  CurvedAnimation _curved(Animation<double> parent) {
    return CurvedAnimation(
      parent: parent,
      curve: AlistenCurves.standard,
      reverseCurve: AlistenCurves.exit,
    );
  }

  @override
  void initState() {
    super.initState();
    _entering = _curved(widget.animation);
    _covered = _curved(widget.secondaryAnimation);
  }

  @override
  void didUpdateWidget(_PageMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != oldWidget.animation) {
      _entering.dispose();
      _entering = _curved(widget.animation);
    }
    if (widget.secondaryAnimation != oldWidget.secondaryAnimation) {
      _covered.dispose();
      _covered = _curved(widget.secondaryAnimation);
    }
  }

  @override
  void dispose() {
    _entering.dispose();
    _covered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: (widget.rises ? _fromBottom : _fromRight).animate(_entering),
      child: SlideTransition(
        position: _receded.animate(_covered),
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            IgnorePointer(
              child: FadeTransition(
                opacity: _dimmed.animate(_covered),
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ],
        ),
      ),
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
