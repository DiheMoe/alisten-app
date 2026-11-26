import 'dart:async';
import 'dart:ui' as ui;

import 'package:alisten/core/cache/cached_cover_image.dart';
import 'package:alisten/core/cache/cover_cache.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/cover_palette.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/desktop_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final coverImageSourceProvider = Provider<ImageProvider Function(String url)>((
  ref,
) {
  final cache = ref.watch(coverCacheProvider);
  return (url) => CachedCoverImage(url, cache);
});

final coverSchemeLoaderProvider = Provider<CoverSchemeLoader>((ref) {
  return CoverPalette(
    ImageCoverSchemeLoader(ref.watch(coverImageSourceProvider)),
  );
});

/// 房间外的页面：只用品牌配色，跟随设置里的深浅模式，不随封面变化。
final appThemeProvider = Provider<AppThemes>((ref) {
  final mode = switch (ref.watch(
    settingsControllerProvider.select((state) => state.value.theme),
  )) {
    AppTheme.dark => ThemeMode.dark,
    AppTheme.light => ThemeMode.light,
    AppTheme.system => ThemeMode.system,
  };
  final brand = ref.watch(_brandThemesProvider);
  return AppThemes(
    mode: mode,
    light: brand[Brightness.light]!,
    dark: brand[Brightness.dark]!,
  );
});

final class AppThemes {
  const AppThemes({
    required this.mode,
    required this.light,
    required this.dark,
    this.tinted = const {},
  });

  final ThemeMode mode;
  final ThemeData light;
  final ThemeData dark;

  /// 已经换上封面颜色的深浅，其余的还是品牌色。
  final Set<Brightness> tinted;
}

// 每个容器各建一份，不用顶层缓存：ThemeData 构建时读取当时的平台，
// 顶层缓存会让后续测试沿用第一次构建时的平台。
final _brandThemesProvider = Provider<Map<Brightness, ThemeData>>((ref) {
  return {
    for (final brightness in Brightness.values)
      brightness: buildAlistenTheme(AlistenColors.brandScheme(brightness)),
  };
});

final _roomBrandThemesProvider = Provider<Map<Brightness, ThemeData>>((ref) {
  return {
    for (final brightness in Brightness.values)
      brightness: buildAlistenTheme(
        AlistenColors.brandScheme(brightness),
        immersive: true,
      ),
  };
});

/// 房间内（播放、歌词、队列、聊天、点歌、迷你播放条，以及从这些地方打开的
/// 面板）的主题：颜色取自正在播放的封面，深浅跟随设置。
final roomThemeProvider = NotifierProvider<RoomThemeController, AppThemes>(
  RoomThemeController.new,
);

final class RoomThemeController extends Notifier<AppThemes> {
  @override
  AppThemes build() {
    final mode = ref.watch(appThemeProvider.select((themes) => themes.mode));
    final brand = ref.watch(_roomBrandThemesProvider);
    final cover = ref.watch(
      nowPlayingProvider.select((playing) => playing?.entry.meta.coverUrl),
    );
    if (cover == null || cover.isEmpty) {
      return AppThemes(
        mode: mode,
        light: brand[Brightness.light]!,
        dark: brand[Brightness.dark]!,
      );
    }

    final loader = ref.watch(coverSchemeLoaderProvider);
    for (final brightness in Brightness.values) {
      final shown = switch (mode) {
        ThemeMode.system => true,
        ThemeMode.light => brightness == Brightness.light,
        ThemeMode.dark => brightness == Brightness.dark,
      };
      // 重新构建后 notifier 不变，但 `ref` 会换成新一次构建的；只有本次构建的
      // ref 能判断读取结果是否过期。
      if (shown) {
        unawaited(_showCover(ref, loader, cover, brand[brightness]!));
      }
    }
    // 封面读完之前沿用屏幕上现有的颜色，换歌时从上一首直接过渡到下一首，
    // 不经过品牌色。
    final previous = stateOrNull;
    return AppThemes(
      mode: mode,
      light: previous?.light ?? brand[Brightness.light]!,
      dark: previous?.dark ?? brand[Brightness.dark]!,
      tinted: previous?.tinted ?? const {},
    );
  }

  Future<void> _showCover(
    Ref scope,
    CoverSchemeLoader loader,
    String cover,
    ThemeData brand,
  ) async {
    final brightness = brand.brightness;
    ThemeData theme;
    var read = true;
    try {
      theme = buildAlistenTheme(
        await loader.load(cover, brightness),
        immersive: true,
      );
    } on Object {
      AppLog.debug('theme', 'cover colours not read');
      theme = brand;
      read = false;
    }
    if (!scope.mounted) return;
    final tinted = {...state.tinted};
    if (read) {
      tinted.add(brightness);
    } else {
      tinted.remove(brightness);
    }
    state = switch (brightness) {
      Brightness.light => AppThemes(
        mode: state.mode,
        light: theme,
        dark: state.dark,
        tinted: tinted,
      ),
      Brightness.dark => AppThemes(
        mode: state.mode,
        light: state.light,
        dark: theme,
        tinted: tinted,
      ),
    };
  }
}

/// 给房间内的内容套上 [roomThemeProvider] 中当前深浅的主题，换歌时颜色渐变
/// 过去。
class RoomTheme extends ConsumerStatefulWidget {
  const RoomTheme({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<RoomTheme> createState() => _RoomThemeState();
}

class _RoomThemeState extends ConsumerState<RoomTheme> {
  bool? _tinted;

  @override
  Widget build(BuildContext context) {
    final themes = ref.watch(roomThemeProvider);
    final dark = switch (themes.mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    final tinted = themes.tinted.contains(
      dark ? Brightness.dark : Brightness.light,
    );
    final data = dark ? themes.dark : themes.light;
    final duration = AlistenDurations.of(context, AlistenDurations.theme);
    if (!isDesktopPlatform) {
      return AnimatedTheme(data: data, duration: duration, child: widget.child);
    }
    // 品牌色第一次换成封面的颜色时直接换上：这多半是刚进房间，页面正在打开。
    final first = _tinted == false && tinted;
    _tinted = tinted;
    return _ThemeDissolve(
      data: data,
      duration: first ? Duration.zero : duration,
      child: widget.child,
    );
  }
}

// 桌面窗口大，逐帧渐变主题要把整个窗口每帧重建一遍，跟不上。这里先拍下旧颜色
// 的样子盖在上面，一次换上新主题，再让旧的样子淡出。
class _ThemeDissolve extends StatefulWidget {
  const _ThemeDissolve({
    required this.data,
    required this.duration,
    required this.child,
  });

  final ThemeData data;
  final Duration duration;
  final Widget child;

  @override
  State<_ThemeDissolve> createState() => _ThemeDissolveState();
}

class _ThemeDissolveState extends State<_ThemeDissolve>
    with SingleTickerProviderStateMixin {
  final _look = GlobalKey();
  late final _old = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status.isDismissed && _picture != null) setState(_drop);
    });
  late ThemeData _applied = widget.data;
  ui.Image? _picture;
  bool _waiting = false;

  void _drop() {
    _picture?.dispose();
    _picture = null;
  }

  @override
  void didUpdateWidget(_ThemeDissolve oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data == _applied || _waiting) return;
    if (widget.duration == Duration.zero) {
      _applied = widget.data;
      return;
    }
    // 等这一帧画完再拍：画面完整，颜色还是旧的。
    _waiting = true;
    WidgetsBinding.instance.addPostFrameCallback(_swap);
  }

  void _swap(Duration _) {
    _waiting = false;
    if (!mounted) return;
    final look = _look.currentContext?.findRenderObject();
    var paintable = look is RenderRepaintBoundary && !look.size.isEmpty;
    // 只在调试模式下有效：这时拍会触发断言，改为直接换上。
    assert(() {
      paintable = paintable && !look!.debugNeedsPaint;
      return true;
    }());
    setState(() {
      if (paintable) {
        _drop();
        _picture = (look! as RenderRepaintBoundary).toImageSync(
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        _old
          ..value = 1
          ..animateBack(0, duration: widget.duration, curve: Curves.easeOut);
      }
      _applied = widget.data;
    });
  }

  @override
  void dispose() {
    _old.dispose();
    _drop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picture = _picture;
    // 旧的样子也在拍照的范围里：渐变途中又换主题时，接着当时的画面淡出。
    return RepaintBoundary(
      key: _look,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Theme(data: _applied, child: widget.child),
          if (picture != null)
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _old,
                  child: RawImage(image: picture, fit: BoxFit.fill),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
