import 'package:alisten/domain/track/track.dart';

final class Listen {
  const Listen({
    required this.track,
    required this.meta,
    required this.heardAtMs,
  });

  final Track track;
  final TrackMeta meta;

  /// 最近一次听到时这首歌的开播时间，不是成员听到的时刻。
  final int heardAtMs;

  bool isSameTrackAs(Listen other) => trackKey(track) == trackKey(other.track);
}
