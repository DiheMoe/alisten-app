enum TrackSource { netease, qq, bilibili, link }

final class Track {
  const Track({required this.source, required this.id});

  final TrackSource source;
  final String id;
}

String trackKey(Track track) => '${track.source.name}:${track.id}';

final class TrackMeta {
  const TrackMeta({
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.pageUrl,
    required this.durationMs,
  });

  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final String pageUrl;
  final int durationMs;
}

final class TrackSummary {
  const TrackSummary({required this.track, required this.meta});

  final Track track;
  final TrackMeta meta;
}

final class PlaylistSummary {
  const PlaylistSummary({
    required this.source,
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.creator,
    required this.description,
    required this.trackCount,
    required this.playCount,
  });

  final TrackSource source;
  final String id;
  final String name;
  final String coverUrl;
  final String creator;
  final String description;
  final int trackCount;
  final int playCount;
}
