import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final lyricsProvider = Provider<List<LyricLine>>((ref) {
  final source = ref.watch(
    roomControllerProvider.select((state) {
      final nowPlaying = state.snapshot?.nowPlaying;
      return (
        nowPlaying?.lyric,
        nowPlaying?.lyricWords,
        nowPlaying?.lyricTrans,
      );
    }),
  );
  return buildLyricLines(
    lyric: source.$1 ?? '',
    words: source.$2,
    translation: source.$3,
  );
});

/// 正在唱的这一句；开唱前、间奏和没有在本机播放时为 null。
final currentLyricProvider = Provider<String?>((ref) {
  final lines = ref.watch(lyricsProvider);
  return ref.watch(
    playbackControllerProvider.select((playback) {
      if (playback.status != LocalPlaybackStatus.playing) return null;
      final index = lineIndexAt(lines, playback.positionMs);
      if (index < 0 || lines[index].isBlank) return null;
      return lines[index].text;
    }),
  );
});
