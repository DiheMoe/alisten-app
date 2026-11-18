import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/admin/application/admin_models.dart';

const _kib = 1024;
const _mib = 1024 * 1024;
const _gib = 1024 * 1024 * 1024;

String formatBytes(int bytes) {
  String one(double value) => value.toStringAsFixed(1);
  if (bytes < _kib) return '$bytes B';
  if (bytes < _mib) return '${one(bytes / _kib)} KiB';
  if (bytes < _gib) return '${one(bytes / _mib)} MiB';
  return '${one(bytes / _gib)} GiB';
}

String mediaOrigin(StoredTrack track) => switch (track.source) {
  TrackSource.netease => '网易云音乐',
  TrackSource.qq => 'QQ 音乐',
  TrackSource.bilibili => '哔哩哔哩',
  TrackSource.link => switch (Uri.tryParse(track.link)?.host) {
    final host? when host.isNotEmpty => host,
    _ => '链接',
  },
};

String mediaByline(StoredTrack track) => track.artist.isEmpty
    ? mediaOrigin(track)
    : '${track.artist} · ${mediaOrigin(track)}';

String formatStoredDate(int epochMs, DateTime now) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final day = '${time.month} 月 ${time.day} 日';
  return time.year == now.year ? day : '${time.year} 年 $day';
}

String formatLastPlayed(int? epochMs, DateTime now) {
  if (epochMs == null) return '从未播放';
  final ago = now.difference(DateTime.fromMillisecondsSinceEpoch(epochMs));
  if (ago.inMinutes < 1) return '刚刚播放';
  if (ago.inHours < 1) return '${ago.inMinutes} 分钟前播放';
  if (ago.inDays < 1) return '${ago.inHours} 小时前播放';
  if (ago.inDays < 30) return '${ago.inDays} 天前播放';
  return '${formatStoredDate(epochMs, now)}播放';
}

String mediaDetails(StoredTrack track, DateTime now) =>
    '${formatBytes(track.bytes)} · '
    '${formatStoredDate(track.storedAtMs, now)}存储 · '
    '${formatLastPlayed(track.lastPlayedAtMs, now)}';
