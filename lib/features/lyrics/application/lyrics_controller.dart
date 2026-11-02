import 'package:alisten/domain/playback/lrc.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final lyricsProvider = Provider<List<LyricLine>>((ref) {
  final lyric = ref.watch(
    roomControllerProvider.select((state) => state.snapshot?.nowPlaying?.lyric),
  );
  return parseLrc(lyric ?? '');
});
