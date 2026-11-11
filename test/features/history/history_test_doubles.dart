import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/history/index.dart';

final class FakeHistoryExporter implements HistoryExporter {
  List<Listen> listens = [];
  DateTime? exportedAt;

  @override
  Future<void> export(List<Listen> listens, DateTime exportedAt) async {
    this.listens = listens;
    this.exportedAt = exportedAt;
  }
}

/// 歌名同时用作曲目 ID，列表行与记录可以按歌名对应。
Listen heard(
  String title, {
  int at = 0,
  TrackSource source = TrackSource.netease,
  String artist = '歌手',
  String album = '专辑',
  String coverUrl = '',
}) {
  return Listen(
    track: Track(source: source, id: title),
    meta: TrackMeta(
      title: title,
      artist: artist,
      album: album,
      coverUrl: coverUrl,
      pageUrl: '',
      durationMs: 180000,
    ),
    heardAtMs: at,
  );
}
