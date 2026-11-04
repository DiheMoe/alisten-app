import 'package:alisten/domain/playback/lrc.dart';
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
