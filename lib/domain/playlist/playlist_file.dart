import 'dart:convert';

import 'package:alisten/domain/track/track.dart';

const playlistFileTrackLimit = 1000;
const notPlaylistFileText = '这个文件不是导出的歌单。';
const emptyPlaylistFileText = '这个歌单文件里没有歌。';

String badTrackText(int number) => '文件里的第 $number 首歌缺少音源或 ID，没有导入。';

const _format = 'alisten.playlist';
const _maxDurationMs = 86400000;

/// 对应协议的 `ImportedTrack`，另起名字以免与生成的 DTO 混淆。
final class PlaylistFileTrack {
  const PlaylistFileTrack({
    required this.track,
    required this.title,
    this.artist,
    this.album,
    required this.durationMs,
    this.coverUrl,
    this.pageUrl,
  });

  final Track track;
  final String title;
  final String? artist;
  final String? album;
  final int durationMs;
  final String? coverUrl;
  final String? pageUrl;
}

sealed class PlaylistFileResult {
  const PlaylistFileResult();
}

final class PlaylistFile extends PlaylistFileResult {
  const PlaylistFile({
    required this.name,
    required this.tracks,
    required this.truncated,
  });

  final String name;
  final List<PlaylistFileTrack> tracks;

  /// 文件里超过 [playlistFileTrackLimit] 首，只取了前面的。
  final bool truncated;
}

final class PlaylistFileProblem extends PlaylistFileResult {
  const PlaylistFileProblem(this.message);

  final String message;
}

/// 与 Web 的导出相同：`exportedAt` 精确到毫秒，与 `toISOString()` 一致。
String playlistExportJson(
  String name,
  List<TrackSummary> items,
  int exportedAtMs,
) {
  return const JsonEncoder.withIndent('  ').convert({
    'format': _format,
    'name': name,
    'exportedAt': DateTime.fromMillisecondsSinceEpoch(
      exportedAtMs,
      isUtc: true,
    ).toIso8601String(),
    'tracks': [
      for (final item in items)
        {
          'source': item.track.source.name,
          'id': item.track.id,
          'title': item.meta.title,
          'artist': item.meta.artist,
          'album': item.meta.album,
          'durationMs': item.meta.durationMs,
          'coverUrl': item.meta.coverUrl,
          'pageUrl': item.meta.pageUrl,
        },
    ],
  });
}

// Windows 的文件名不能含 \ / : * ? " < > | 和控制字符，其他系统也不能含 /。
final _unsafeFileName = RegExp(r'[\\/:*?"<>|\p{Cc}]', unicode: true);

String playlistExportFileName(String name) =>
    '${name.replaceAll(_unsafeFileName, '_')}.json';

final _sources = {for (final source in TrackSource.values) source.name: source};

/// 规则与 Web 一致：文件可以随意改写，元数据的类型不对时当作没有，由服务端决定
/// 用不用；音源和 ID 不对就认不出是哪首歌，整个文件不导入。
PlaylistFileResult parsePlaylistFile(String content) {
  final Object? json;
  try {
    json = jsonDecode(content);
  } on FormatException {
    return const PlaylistFileProblem(notPlaylistFileText);
  }
  if (json is! Map<String, Object?> || json['format'] != _format) {
    return const PlaylistFileProblem(notPlaylistFileText);
  }
  final entries = json['tracks'];
  if (entries is! List<Object?>) {
    return const PlaylistFileProblem(notPlaylistFileText);
  }
  if (entries.isEmpty) return const PlaylistFileProblem(emptyPlaylistFileText);
  final tracks = <PlaylistFileTrack>[];
  for (final (index, entry) in entries.take(playlistFileTrackLimit).indexed) {
    final track = _track(entry);
    if (track == null) return PlaylistFileProblem(badTrackText(index + 1));
    tracks.add(track);
  }
  final name = json['name'];
  return PlaylistFile(
    name: name is String ? name : '',
    tracks: tracks,
    truncated: entries.length > playlistFileTrackLimit,
  );
}

PlaylistFileTrack? _track(Object? entry) {
  if (entry is! Map<String, Object?>) return null;
  final source = _sources[entry['source']];
  final id = entry['id'];
  if (source == null || id is! String || id.isEmpty) return null;
  final title = entry['title'];
  return PlaylistFileTrack(
    track: Track(source: source, id: id),
    title: title is String ? title : '',
    artist: _text(entry['artist']),
    album: _text(entry['album']),
    durationMs: _duration(entry['durationMs']),
    coverUrl: _text(entry['coverUrl']),
    pageUrl: _text(entry['pageUrl']),
  );
}

String? _text(Object? value) => value is String ? value : null;

// JSON 里的 1.0 也算整数值，与 Web 的 `Number.isInteger` 一致。
int _duration(Object? value) {
  final whole = switch (value) {
    final int number => number,
    final double number when number == number.truncateToDouble() =>
      number.isFinite ? number.toInt() : null,
    _ => null,
  };
  return whole != null && whole >= 0 && whole <= _maxDurationMs ? whole : 0;
}
