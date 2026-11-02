import 'dart:async';

import 'package:alisten/core/cache/cached_cover_image.dart';
import 'package:alisten/core/cache/cover_cache.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/cover_palette.dart';
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

final appThemeProvider = NotifierProvider<AppThemeController, AppThemes>(
  AppThemeController.new,
);

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

final class AppThemeController extends Notifier<AppThemes> {
  @override
  AppThemes build() {
    final mode = switch (ref.watch(
      settingsControllerProvider.select((state) => state.value.theme),
    )) {
      AppTheme.dark => ThemeMode.dark,
      AppTheme.light => ThemeMode.light,
      AppTheme.system => ThemeMode.system,
    };
    final brand = ref.watch(_brandThemesProvider);
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
    // 重新构建后 notifier 不变，但 `ref` 会换成新一次构建的；只有本次构建的 ref
    // 能判断读取结果是否过期。
    final scope = ref;
    for (final brightness in Brightness.values) {
      final shown = switch (mode) {
        ThemeMode.system => true,
        ThemeMode.light => brightness == Brightness.light,
        ThemeMode.dark => brightness == Brightness.dark,
      };
      if (shown) {
        unawaited(_showCover(scope, loader, cover, brand[brightness]!));
      }
    }
    // 封面读完之前沿用屏幕上现有的颜色，换歌时从上一首直接过渡到
    // 下一首，不经过品牌色。
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
      theme = buildAlistenTheme(await loader.load(cover, brightness));
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
