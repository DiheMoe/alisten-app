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

  group('parseWordLyrics', () {
    List<String> texts(List<LyricLine> lines) =>
        lines.where((line) => !line.isBlank).map((line) => line.text).toList();

    test('reads absolute times, and the line text is its words', () {
      final line = parseWordLyrics('[1000,900](1000,400,0)故(1400,500,0)事')
          .first;

      expect(line.timeMs, 1000);
      expect(line.endMs, 1900);
      expect(line.text, '故事');
      expect(line.words!.map((word) => word.startMs), [1000, 1400]);
      expect(line.words!.map((word) => word.durationMs), [400, 500]);
      expect(line.words!.last.endMs, 1900);
    });

    test('keeps brackets and spaces, splitting only on whole time tags', () {
      final line = parseWordLyrics(
        '[0,1000](0,500,0)(ooh) (500,250,0)[yeah] (750,250,0)(1,2)',
      ).first;

      expect(line.words!.map((word) => word.text), [
        '(ooh) ',
        '[yeah] ',
        '(1,2)',
      ]);
      expect(line.text, '(ooh) [yeah] (1,2)');
    });

    test('skips rows that are not lines, have no words, or are all blank, '
        'and copes with CRLF', () {
      final lines = parseWordLyrics(
        '{"t":0,"c":[]}\r\n\r\n[0,500]\r\n[500,500](500,500,0)  \r\n'
        '注[700,100](700,100,0)释\r\n[1000,500](1000,500,0)词\r\n',
      );

      expect(lines.map((line) => line.text), ['词', '']);
      expect(lines.first.words!.single.text, '词');
    });

    test('a word of only spaces joins the word before it, and is dropped at '
        'the head of a line', () {
      final line = parseWordLyrics(
        '[0,1500](0,500,0) (500,500,0)Hello(1000,0,0) (1000,500,0)love',
      ).first;

      expect(line.words!.map((word) => word.text), ['Hello ', 'love']);
      expect(line.words!.map((word) => word.startMs), [500, 1000]);
      expect(line.text, 'Hello love');
    });

    test('sorts lines by start time, keeping the order of equal times', () {
      expect(
        texts(
          parseWordLyrics('[2000,500](2000,500,0)二\n[1000,500](1000,500,0)一'),
        ),
        ['一', '二'],
      );
      expect(
        texts(
          parseWordLyrics('[1000,500](1000,500,0)先\n[1000,500](1000,500,0)后'),
        ),
        ['先', '后'],
      );
    });

    test(
      'adds a blank line where an interlude begins, but not for a breath',
      () {
        final lines = parseWordLyrics(
          '[0,1000](0,1000,0)一\n[1500,1000](1500,1000,0)二\n'
          '[20000,1000](20000,1000,0)三',
        );

        expect(lines.map((line) => (line.timeMs, line.text)), [
          (0, '一'),
          (1500, '二'),
          (2500, ''),
          (20000, '三'),
          (21000, ''),
        ]);
      },
    );

    test('a gap of exactly three seconds is an interlude', () {
      final lines = parseWordLyrics(
        '[0,1000](0,1000,0)一\n[4000,1000](4000,1000,0)二',
      );

      expect(lines[1].isBlank, isTrue);
      expect(lines[1].timeMs, 1000);
    });

    test('a time too long to read skips its line instead of throwing', () {
      final lines = parseWordLyrics(
        '[99999999999999999999,1](0,1,0)坏\n'
        '[0,1](99999999999999999999,1,0)坏\n'
        '[1000,500](1000,500,0)好',
      );

      expect(lines.first.text, '好');
    });

    test('a time past a day skips its line, so sums cannot wrap around', () {
      final lines = parseWordLyrics(
        '[9223372036854775000,9223372036854775000](0,1,0)坏\n'
        '[0,1](86400001,1,0)坏\n'
        '[1000,500](1000,500,0)好',
      );

      expect(lines.first.text, '好');
    });

    test('a trailing time tag with no text adds no word', () {
      final line = parseWordLyrics('[0,1000](0,500,0)花(500,500,0)').first;

      expect(line.words!.map((word) => word.text), ['花']);
    });

    test('the first word loses leading spaces and the last trailing ones', () {
      final line = parseWordLyrics('[0,1000](0,500,0) Hello (500,500,0)love ')
          .first;

      expect(line.text, 'Hello love');
      expect(line.words!.map((word) => word.text), ['Hello ', 'love']);
    });

    test('reads the sample the NetEase adapter stores', () {
      final lines = parseWordLyrics(
        '[16350,3810](16350,600,0)故(16950,600,0)事(19950,210,0)\n'
        '[20160,4000](20160,500,0)从',
      );

      expect(lines.first.text, '故事');
      expect(lines.first.words, hasLength(2));
      expect(lines[1].text, '从');
    });
  });

  group('pairTranslations', () {
    LyricLine line(int timeMs, String text) =>
        LyricLine(timeMs: timeMs, text: text);

    List<String?> paired(List<LyricLine> lines, List<LyricLine> translations) =>
        pairTranslations(
          lines,
          translations,
        ).map((line) => line.translation).toList();

    test('a translation goes to the nearest line, allowing for rounding', () {
      expect(
        paired(
          [line(1000, '一'), line(3000, '二')],
          [line(991, 'one'), line(3009, 'two')],
        ),
        ['one', 'two'],
      );
    });

    test('a translation nearer the later line goes to it', () {
      expect(paired([line(1000, '一'), line(1400, '二')], [line(1390, 'two')]), [
        null,
        'two',
      ]);
    });

    test('more than 500 ms away means this line has no translation', () {
      expect(paired([line(1000, '一')], [line(1500, 'one')]), ['one']);
      expect(paired([line(1000, '一')], [line(1501, 'one')]), [null]);
    });

    test('a line without a translation does not borrow its neighbour\'s', () {
      expect(paired([line(1000, '一'), line(1300, '二')], [line(1000, 'one')]), [
        'one',
        null,
      ]);
    });

    test('of several candidates a line keeps the nearest', () {
      expect(
        paired(
          [line(1000, '一')],
          [line(800, 'far'), line(990, 'near'), line(1200, 'far too')],
        ),
        ['near'],
      );
    });

    test('a tie between lines goes to the earlier one', () {
      expect(paired([line(1000, '一'), line(1000, '二')], [line(1000, 'one')]), [
        'one',
        null,
      ]);
      expect(paired([line(1000, '一'), line(1200, '二')], [line(1100, 'one')]), [
        'one',
        null,
      ]);
    });

    test('blank lines and empty translations take no part', () {
      expect(
        paired(
          [line(1000, '一'), line(1100, ''), line(5000, '二')],
          [line(1100, 'one'), line(5000, '')],
        ),
        ['one', null, null],
      );
    });

    test('no lines is not an error', () {
      expect(pairTranslations(const [], [line(1000, 'one')]), isEmpty);
    });

    test('keeps the word timings of a paired line', () {
      final lines = parseWordLyrics('[1000,500](1000,500,0)词');

      final result = pairTranslations(lines, [line(1000, 'word')]);

      expect(result.first.translation, 'word');
      expect(result.first.words, hasLength(1));
      expect(result.first.endMs, 1500);
    });
  });

  group('buildLyricLines', () {
    test('word lyrics give the lines, and translations pair with them', () {
      final lines = buildLyricLines(
        lyric: '[00:01.00]行级歌词',
        words: '[1000,500](1000,500,0)逐(1250,250,0)字',
        translation: '[ti:标题]\n[00:01.00]Word by word',
      );

      expect(lines.first.text, '逐字');
      expect(lines.first.translation, 'Word by word');
      expect(lines.first.words, hasLength(2));
    });

    test('without word lyrics the lines stay whole', () {
      final lines = buildLyricLines(lyric: '[00:01.00]行级歌词');

      expect(lines.single.text, '行级歌词');
      expect(lines.single.words, isNull);
    });

    test('word lyrics with nothing to read fall back to the lyric', () {
      final lines = buildLyricLines(lyric: '[00:01.00]行级歌词', words: '{"t":0}');

      expect(lines.single.text, '行级歌词');
    });

    test('an empty lyric gives no lines', () {
      expect(buildLyricLines(lyric: ''), isEmpty);
    });

    test('a long intro starts with a blank line at zero', () {
      final lines = buildLyricLines(lyric: '[00:07.00]一');

      expect(lines.map((line) => (line.timeMs, line.text)), [
        (0, ''),
        (7000, '一'),
      ]);
    });

    test('a short intro adds no blank line', () {
      expect(buildLyricLines(lyric: '[00:06.99]一'), hasLength(1));
    });

    test('only the first line that has text counts for the intro', () {
      final lines = buildLyricLines(lyric: '[00:01.00]\n[00:09.00]一');

      expect(lines.map((line) => (line.timeMs, line.text)), [
        (0, ''),
        (1000, ''),
        (9000, '一'),
      ]);
    });
  });
}
