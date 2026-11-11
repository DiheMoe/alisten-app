import 'package:alisten/domain/playlist/playlist_date.dart';
import 'package:flutter_test/flutter_test.dart';

// 本地时间；天数按年月日计算，不写跨夏令时的用例。
int _at(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    DateTime(year, month, day, hour, minute).millisecondsSinceEpoch;

void main() {
  final now = _at(2026, 11, 11, 9, 30);

  test('today and yesterday carry the time', () {
    expect(formatPlaylistDate(_at(2026, 11, 11, 8, 5), now), '今天 08:05');
    expect(formatPlaylistDate(_at(2026, 11, 10, 23, 59), now), '昨天 23:59');
  });

  test('a time later today is today, and one tomorrow is a date', () {
    expect(formatPlaylistDate(_at(2026, 11, 11, 23), now), '今天 23:00');
    expect(formatPlaylistDate(_at(2026, 11, 12, 8), now), '11月12日');
  });

  test('the same year leaves the year out, other years keep it', () {
    expect(formatPlaylistDate(_at(2026, 11, 9, 12), now), '11月9日');
    expect(formatPlaylistDate(_at(2026, 3, 2, 12), now), '3月2日');
    expect(formatPlaylistDate(_at(2025, 12, 31, 12), now), '2025年12月31日');
  });

  test('just past midnight the day before is yesterday', () {
    final night = _at(2026, 11, 11, 0, 1);

    expect(formatPlaylistDate(_at(2026, 11, 10, 23, 59), night), '昨天 23:59');
    expect(formatPlaylistDate(_at(2026, 11, 9, 23, 59), night), '11月9日');
  });

  test('yesterday across a new year is still yesterday', () {
    expect(
      formatPlaylistDate(_at(2025, 12, 31, 22), _at(2026, 1, 1, 8)),
      '昨天 22:00',
    );
  });
}
