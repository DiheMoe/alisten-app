import 'dart:async';
import 'dart:ui' as ui;

import 'package:alisten/app/app_theme.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/cover_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/cache/cover_cache_test_doubles.dart';
import '../domain/room/room_fixtures.dart';
import '../features/playback/playback_test_doubles.dart' show nowPlayingWith;
import 'app_test_harness.dart';

const _coverA = 'https://example.com/cover.jpg';
const _coverB = 'https://example.com/cover-b.jpg';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeCoverLoader covers;
  late void Function(NowPlaying? playing) play;

  setUp(() => covers = _FakeCoverLoader());

  Future<ProviderContainer> open({
    NowPlaying? playing,
    Map<String, Object> stored = const {},
  }) async {
    final track = NotifierProvider<_Track, NowPlaying?>(() => _Track(playing));
    final container = ProviderContainer(
      overrides: [
        ...await alistenAppOverrides(preferences: stored),
        nowPlayingProvider.overrideWith((ref) => ref.watch(track)),
        coverSchemeLoaderProvider.overrideWithValue(covers),
      ],
    );
    addTearDown(container.dispose);
    container.listen(appThemeProvider, (_, _) {});
    play = (playing) => container.read(track.notifier).play(playing);
    return container;
  }

  Color primary(ProviderContainer container, Brightness brightness) {
    final themes = container.read(appThemeProvider);
    return switch (brightness) {
      Brightness.light => themes.light.colorScheme.primary,
      Brightness.dark => themes.dark.colorScheme.primary,
    };
  }

  void expectColoursOf(ProviderContainer container, String cover) {
    for (final brightness in Brightness.values) {
      expect(
        primary(container, brightness),
        _FakeCoverLoader.scheme(cover, brightness).primary,
        reason: '$brightness',
      );
    }
  }

  ColorScheme brand(Brightness brightness) => ColorScheme.fromSeed(
    seedColor: const Color(0xFF6D5BFF),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
  );

  test('without a playing cover the brand colours are shown', () async {
    final container = await open();
    await pumpEventQueue();

    final themes = container.read(appThemeProvider);
    expect(themes.light.brightness, Brightness.light);
    expect(themes.light.colorScheme.primary, brand(Brightness.light).primary);
    expect(themes.dark.brightness, Brightness.dark);
    expect(themes.dark.colorScheme.primary, brand(Brightness.dark).primary);
    expect(themes.dark.extension<AlistenColors>(), isNotNull);
    expect(themes.dark.splashFactory, NoSplash.splashFactory);
    expect(covers.reads, isEmpty);
  });

  test(
    'each app builds its brand themes for the platform it runs on',
    () async {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final ios = await open();
      debugDefaultTargetPlatformOverride = null;
      final android = await open();

      for (final (container, platform) in [
        (ios, TargetPlatform.iOS),
        (android, TargetPlatform.android),
      ]) {
        final themes = container.read(appThemeProvider);
        expect(themes.light.platform, platform);
        expect(themes.dark.platform, platform);
      }
    },
  );

  test('the brand themes stay the same objects while no cover plays', () async {
    final container = await open(stored: {'alisten.theme': 'light'});
    await pumpEventQueue();
    final first = container.read(appThemeProvider);

    await container
        .read(settingsControllerProvider.notifier)
        .setTheme(AppTheme.dark);
    await pumpEventQueue();
    final second = container.read(appThemeProvider);

    expect(second.mode, ThemeMode.dark);
    expect(second.light, same(first.light));
    expect(second.dark, same(first.dark));
  });

  test('the playing cover decides the colours once it is read', () async {
    final container = await open(playing: nowPlayingWith());

    // 封面读取完成前，显示的颜色不变。
    expect(
      container.read(appThemeProvider).dark.colorScheme.primary,
      brand(Brightness.dark).primary,
    );
    await pumpEventQueue();

    final themes = container.read(appThemeProvider);
    expect(
      themes.light.colorScheme.primary,
      _FakeCoverLoader.scheme(_coverA, Brightness.light).primary,
    );
    expect(
      themes.dark.colorScheme.primary,
      _FakeCoverLoader.scheme(_coverA, Brightness.dark).primary,
    );
    expect(
      covers.reads,
      unorderedEquals([
        (testTrackMeta.coverUrl, Brightness.light),
        (testTrackMeta.coverUrl, Brightness.dark),
      ]),
    );
  });

  test('the brightness follows the settings', () async {
    final container = await open(
      playing: nowPlayingWith(),
      stored: {'alisten.theme': 'light'},
    );
    await pumpEventQueue();

    var themes = container.read(appThemeProvider);
    expect(themes.mode, ThemeMode.light);
    expect(
      themes.light.colorScheme.primary,
      _FakeCoverLoader.scheme(_coverA, Brightness.light).primary,
    );
    // 只读取当前深浅模式下的封面配色。
    expect(covers.reads, [(testTrackMeta.coverUrl, Brightness.light)]);

    await container
        .read(settingsControllerProvider.notifier)
        .setTheme(AppTheme.dark);
    await pumpEventQueue();
    themes = container.read(appThemeProvider);
    expect(themes.mode, ThemeMode.dark);
    expect(
      themes.dark.colorScheme.primary,
      _FakeCoverLoader.scheme(_coverA, Brightness.dark).primary,
    );

    await container
        .read(settingsControllerProvider.notifier)
        .setTheme(AppTheme.system);
    await pumpEventQueue();
    expect(container.read(appThemeProvider).mode, ThemeMode.system);
  });

  test(
    'a track change goes from one cover to the next, not via the brand',
    () async {
      final container = await open(playing: _playingCover(_coverA));
      await pumpEventQueue();
      expectColoursOf(container, _coverA);

      final readB = covers.held[_coverB] = Completer<void>();
      play(_playingCover(_coverB));
      await pumpEventQueue();
      // 读取下一张封面期间，屏幕上的颜色保持不变。
      expectColoursOf(container, _coverA);

      readB.complete();
      await pumpEventQueue();
      expectColoursOf(container, _coverB);
    },
  );

  test(
    'a cover read late does not replace the next track\'s colours',
    () async {
      final readA = covers.held[_coverA] = Completer<void>();
      final container = await open(playing: _playingCover(_coverA));
      await pumpEventQueue();

      play(_playingCover(_coverB));
      await pumpEventQueue();
      expectColoursOf(container, _coverB);

      readA.complete();
      await pumpEventQueue();
      expectColoursOf(container, _coverB);
    },
  );

  test(
    'a cover read late does not replace the brand once nothing plays',
    () async {
      final readA = covers.held[_coverA] = Completer<void>();
      final container = await open(playing: _playingCover(_coverA));
      await pumpEventQueue();

      play(null);
      await pumpEventQueue();
      readA.complete();
      await pumpEventQueue();

      expect(
        primary(container, Brightness.light),
        brand(Brightness.light).primary,
      );
      expect(
        primary(container, Brightness.dark),
        brand(Brightness.dark).primary,
      );
    },
  );

  test('a cover that cannot be read shows the brand colours', () async {
    covers.unreadable.add(_coverA);
    final container = await open(playing: _playingCover(_coverA));
    await pumpEventQueue();

    expect(covers.reads, isNotEmpty);
    expect(
      primary(container, Brightness.light),
      brand(Brightness.light).primary,
    );
    expect(primary(container, Brightness.dark), brand(Brightness.dark).primary);
  });

  test('cover colours are read through the cover cache', () async {
    final cache = FakeCoverCache(covers: {_coverA: await _png()});
    final container = ProviderContainer(
      overrides: await alistenAppOverrides(coverCache: cache),
    );
    addTearDown(container.dispose);

    final scheme = await container
        .read(coverSchemeLoaderProvider)
        .load(_coverA, Brightness.dark);

    expect(scheme.brightness, Brightness.dark);
    expect(cache.loads, [_coverA]);
  });

  testWidgets('colours change at once when the system removes animations', (
    tester,
  ) async {
    Duration themeAnimation() => tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .themeAnimationDuration;

    await pumpAlistenApp(tester);
    expect(themeAnimation(), const Duration(milliseconds: 600));

    await pumpAlistenApp(
      tester,
      system: const MediaQueryData(disableAnimations: true),
    );
    expect(themeAnimation(), Duration.zero);
  });
}

Future<Uint8List> _png() async {
  final image = await createTestImage(width: 8, height: 8, cache: false);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

final class _FakeCoverLoader implements CoverSchemeLoader {
  static const _seeds = {
    _coverA: Color(0xFF2E9E48),
    _coverB: Color(0xFFE0611F),
  };

  static ColorScheme scheme(String cover, Brightness brightness) {
    return ColorScheme.fromSeed(
      seedColor: _seeds[cover]!,
      brightness: brightness,
    );
  }

  final reads = <(String, Brightness)>[];

  final held = <String, Completer<void>>{};

  final unreadable = <String>{};

  @override
  Future<ColorScheme> load(String url, Brightness brightness) async {
    reads.add((url, brightness));
    await held[url]?.future;
    if (unreadable.contains(url)) throw Exception('cover not read');
    return scheme(url, brightness);
  }
}

final class _Track extends Notifier<NowPlaying?> {
  _Track(this._initial);

  final NowPlaying? _initial;

  @override
  NowPlaying? build() => _initial;

  void play(NowPlaying? playing) => state = playing;
}

NowPlaying _playingCover(String cover) {
  final playing = nowPlayingWith(entryId: cover);
  final entry = playing.entry;
  return NowPlaying(
    entry: QueueEntry(
      id: entry.id,
      track: entry.track,
      meta: TrackMeta(
        title: testTrackMeta.title,
        artist: testTrackMeta.artist,
        album: testTrackMeta.album,
        coverUrl: cover,
        pageUrl: testTrackMeta.pageUrl,
        durationMs: testTrackMeta.durationMs,
      ),
      requestedBy: entry.requestedBy,
      auto: entry.auto,
      likes: entry.likes,
      status: entry.status,
    ),
    mediaUrl: playing.mediaUrl,
    startedAtMs: playing.startedAtMs,
    durationMs: playing.durationMs,
    gain: playing.gain,
    lyric: playing.lyric,
  );
}
