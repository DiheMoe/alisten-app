import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/admin/presentation/media_format.dart';
import 'package:flutter_test/flutter_test.dart';

import '../admin_test_doubles.dart';

void main() {
  final now = DateTime(2026, 11, 18, 20);
  int ms(DateTime time) => time.millisecondsSinceEpoch;

  test('sizes read in B, KiB, MiB and GiB with one decimal', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KiB');
    expect(formatBytes(12900000), '12.3 MiB');
    expect(formatBytes(4509715660), '4.2 GiB');
  });

  test('the origin names the platform, or the host of a link', () {
    expect(mediaOrigin(storedTrack(1)), '网易云音乐');
    expect(mediaOrigin(storedTrack(1, source: TrackSource.qq)), 'QQ 音乐');
    expect(mediaOrigin(storedTrack(1, source: TrackSource.bilibili)), '哔哩哔哩');
    expect(
      mediaOrigin(storedTrack(1, source: TrackSource.link)),
      'music.example.com',
    );
  });

  test('the byline is the artist and origin, or the origin alone', () {
    expect(mediaByline(storedTrack(1)), '歌手 · 网易云音乐');
    expect(mediaByline(storedTrack(1, artist: '')), '网易云音乐');
  });

  test('stored dates leave out this year and keep other years', () {
    expect(formatStoredDate(ms(DateTime(2026, 11, 3, 9)), now), '11 月 3 日');
    expect(
      formatStoredDate(ms(DateTime(2025, 12, 31)), now),
      '2025 年 12 月 31 日',
    );
  });

  test('last played reads as how long ago, or never', () {
    expect(formatLastPlayed(null, now), '从未播放');
    expect(
      formatLastPlayed(ms(now.subtract(const Duration(seconds: 20))), now),
      '刚刚播放',
    );
    expect(
      formatLastPlayed(ms(now.subtract(const Duration(minutes: 5))), now),
      '5 分钟前播放',
    );
    expect(
      formatLastPlayed(ms(now.subtract(const Duration(hours: 3))), now),
      '3 小时前播放',
    );
    expect(
      formatLastPlayed(ms(now.subtract(const Duration(days: 3))), now),
      '3 天前播放',
    );
    expect(formatLastPlayed(ms(DateTime(2026, 9, 1)), now), '9 月 1 日播放');
  });
}
