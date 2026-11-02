import 'package:alisten/domain/playback/lrc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'parseLrc handles fractional seconds multiple tags metadata and CRLF',
    () {
      final lines = parseLrc(
        '[ar:artist]\r\n[00:01.5][00:02.34]重复句\r\n[00:03.123]下一句',
      );

      expect(lines.map((line) => line.timeMs), [1500, 2340, 3123]);
      expect(lines.where((line) => line.text == '重复句'), hasLength(2));
    },
  );

  test('parseLrc sorts lines and merges consecutive blank lines', () {
    final lines = parseLrc('[00:02]二\n[00:01]一\n[00:03]\n[00:04]  \n[00:05]五');

    expect(lines.map((line) => line.timeMs), [1000, 2000, 3000, 5000]);
    expect(lines.map((line) => line.text), ['一', '二', '', '五']);
  });

  test('lineIndexAt uses the last line at or before the position', () {
    const lines = [
      LyricLine(timeMs: 1000, text: '一'),
      LyricLine(timeMs: 2000, text: '二'),
      LyricLine(timeMs: 2000, text: '同时间'),
      LyricLine(timeMs: 3000, text: '三'),
    ];

    expect(lineIndexAt(lines, 999), -1);
    expect(lineIndexAt(lines, 1000), 0);
    expect(lineIndexAt(lines, 2000), 2);
    expect(lineIndexAt(lines, 4000), 3);
    expect(lineIndexAt(const [], 0), -1);
  });
}
