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

final _roomBrandThemeProvider = Provider<ThemeData>((ref) {
  return buildAlistenTheme(
    AlistenColors.brandScheme(Brightness.dark),
    immersive: true,
  );
});

/// 房间内（播放、歌词、队列、聊天、点歌、迷你播放条，以及从这些地方打开的
/// 面板）的主题：不论设置里的深浅模式，总是取自正在播放封面的深色。
final roomThemeProvider = NotifierProvider<RoomThemeController, ThemeData>(
  RoomThemeController.new,
);

final class RoomThemeController extends Notifier<ThemeData> {
  @override
  ThemeData build() {
    final brand = ref.watch(_roomBrandThemeProvider);
    final cover = ref.watch(
      nowPlayingProvider.select((playing) => playing?.entry.meta.coverUrl),
    );
    if (cover == null || cover.isEmpty) return brand;

    // 重新构建后 notifier 不变，但 `ref` 会换成新一次构建的；只有本次构建的 ref
    // 能判断读取结果是否过期。
    unawaited(
      _showCover(ref, ref.watch(coverSchemeLoaderProvider), cover, brand),
    );
    // 封面读完之前沿用屏幕上现有的颜色，换歌时从上一首直接过渡到下一首，
    // 不经过品牌色。
    return stateOrNull ?? brand;
  }

  Future<void> _showCover(
    Ref scope,
    CoverSchemeLoader loader,
    String cover,
    ThemeData brand,
  ) async {
    ThemeData theme;
    try {
      theme = buildAlistenTheme(
        await loader.load(cover, Brightness.dark),
        immersive: true,
      );
    } on Object {
      AppLog.debug('theme', 'cover colours not read');
      theme = brand;
    }
    if (scope.mounted) state = theme;
  }
}

/// 给房间内的内容套上 [roomThemeProvider]，换歌时颜色渐变过去。
class RoomTheme extends ConsumerWidget {
  const RoomTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedTheme(
      data: ref.watch(roomThemeProvider),
      duration: AlistenDurations.of(context, AlistenDurations.theme),
      child: child,
    );
  }
}
