import 'dart:async';

import 'package:alisten/core/cache/cached_cover_image.dart';
import 'package:alisten/core/cache/cover_cache.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/cover_palette.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/material.dart';
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
  });

  final ThemeMode mode;
  final ThemeData light;
  final ThemeData dark;
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
    try {
      theme = buildAlistenTheme(
        await loader.load(cover, brightness),
        immersive: true,
      );
    } on Object {
      AppLog.debug('theme', 'cover colours not read');
      theme = brand;
    }
    if (!scope.mounted) return;
    state = switch (brightness) {
      Brightness.light => AppThemes(
        mode: state.mode,
        light: theme,
        dark: state.dark,
      ),
      Brightness.dark => AppThemes(
        mode: state.mode,
        light: state.light,
        dark: theme,
      ),
    };
  }
}

/// 给房间内的内容套上 [roomThemeProvider] 中当前深浅的主题，换歌时颜色渐变
/// 过去。
class RoomTheme extends ConsumerWidget {
  const RoomTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themes = ref.watch(roomThemeProvider);
    final dark = switch (themes.mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    return AnimatedTheme(
      data: dark ? themes.dark : themes.light,
      duration: AlistenDurations.of(context, AlistenDurations.theme),
      child: child,
    );
  }
}
