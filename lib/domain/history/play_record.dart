import 'package:alisten/domain/history/stored_list.dart';
import 'package:alisten/domain/track/track.dart';

const playHistoryLimit = 500;

final class PlayRecord {
  const PlayRecord({
    required this.roomId,
    required this.roomName,
    required this.serverOrigin,
    required this.track,
    required this.meta,
    required this.playedAtMs,
  });

  final String roomId;

  /// 开始保存房间名之前的记录中为空。
  final String roomName;

  /// 规整后的 origin。房间 id 只在所属服务器内有意义，
  /// 所以要与 [roomId] 一起标识房间。
  final String serverOrigin;
  final Track track;
  final TrackMeta meta;
  final int playedAtMs;

  bool isSameSongAs(PlayRecord other) {
    return roomId == other.roomId &&
        serverOrigin == other.serverOrigin &&
        track.source == other.track.source &&
        track.id == other.track.id;
  }

  Map<String, Object?> toJson() {
    return {
      'roomId': roomId,
      'roomName': roomName,
      'serverOrigin': serverOrigin,
      'track': {'source': track.source.name, 'id': track.id},
      'meta': {
        'title': meta.title,
        'artist': meta.artist,
        'album': meta.album,
        'coverUrl': meta.coverUrl,
        'pageUrl': meta.pageUrl,
        'durationMs': meta.durationMs,
      },
      'playedAtMs': playedAtMs,
    };
  }
}

List<PlayRecord> recordPlay(List<PlayRecord> plays, PlayRecord record) {
  // 按读取时的规则校验，传入空的 `legacyServerOrigin`：新记录必须自带服务器。
  // 读不回来的记录不保存，也不能挤掉同一首歌之前的记录。
  if (tryPlayRecord(record.toJson(), legacyServerOrigin: '') == null) {
    return plays;
  }
  final rest = plays
      .where((play) => !play.isSameSongAs(record))
      .toList(growable: false);
  return [record, ...rest].take(playHistoryLimit).toList(growable: false);
}

List<PlayRecord> parsePlays(
  String? stored, {
  required String legacyServerOrigin,
}) {
  final values = readStoredList(stored);
  return values
      .map(
        (value) => tryPlayRecord(value, legacyServerOrigin: legacyServerOrigin),
      )
      .whereType<PlayRecord>()
      .take(playHistoryLimit)
      .toList(growable: false);
}

PlayRecord? tryPlayRecord(Object? value, {required String legacyServerOrigin}) {
  if (value is! Map<String, Object?>) return null;
  final roomId = value['roomId'];
  final roomName = value['roomName'];
  final storedOrigin = value['serverOrigin'];
  final trackJson = value['track'];
  final metaJson = value['meta'];
  final playedAtMs = value['playedAtMs'];
  if (roomId is! String ||
      roomId.isEmpty ||
      playedAtMs is! int ||
      playedAtMs < 0 ||
      playedAtMs > 8640000000000000) {
    return null;
  }
  final serverOrigin = switch (storedOrigin) {
    null || '' => legacyServerOrigin,
    final String origin => origin,
    _ => null,
  };
  if (serverOrigin == null || serverOrigin.isEmpty) return null;
  final track = _tryTrack(trackJson);
  final meta = _tryMeta(metaJson);
  if (track == null || meta == null) return null;
  return PlayRecord(
    roomId: roomId,
    roomName: roomName is String ? roomName : '',
    serverOrigin: serverOrigin,
    track: track,
    meta: meta,
    playedAtMs: playedAtMs,
  );
}

Track? _tryTrack(Object? value) {
  if (value is! Map<String, Object?>) return null;
  final source = value['source'];
  final id = value['id'];
  if (source is! String || id is! String || id.isEmpty) return null;
  for (final candidate in TrackSource.values) {
    if (candidate.name == source) return Track(source: candidate, id: id);
  }
  return null;
}

TrackMeta? _tryMeta(Object? value) {
  if (value is! Map<String, Object?>) return null;
  final durationMs = value['durationMs'];
  if (durationMs is! int || durationMs < 0) return null;
  final texts = <String>[];
  for (final key in ['title', 'artist', 'album', 'coverUrl', 'pageUrl']) {
    final text = value[key];
    if (text is! String) return null;
    texts.add(text);
  }
  return TrackMeta(
    title: texts[0],
    artist: texts[1],
    album: texts[2],
    coverUrl: texts[3],
    pageUrl: texts[4],
    durationMs: durationMs,
  );
}
