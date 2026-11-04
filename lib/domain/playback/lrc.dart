const interludeGapMs = 3000;
const lyricBreakMinimumMs = 7000;
const maxTranslationGapMs = 500;

// 歌曲不会有这么长；更大的值相加会溢出，排序也就乱了。
const _longestLyricMs = 86400000;

final class LyricWord {
  const LyricWord({
    required this.startMs,
    required this.durationMs,
    required this.text,
  });

  final int startMs;
  final int durationMs;
  final String text;

  int get endMs => startMs + durationMs;
}

final class LyricLine {
  const LyricLine({
    required this.timeMs,
    required this.text,
    this.endMs,
    this.words,
    this.translation,
  });

  final int timeMs;
  final String text;

  /// 只有逐字行有。
  final int? endMs;
  final List<LyricWord>? words;
  final String? translation;

  bool get isBlank => text.isEmpty;

  LyricLine _withTranslation(String translation) {
    return LyricLine(
      timeMs: timeMs,
      text: text,
      endMs: endMs,
      words: words,
      translation: translation,
    );
  }
}

final _timeTag = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');
final _wordLineHead = RegExp(r'^\[(\d+),(\d+)\]');
final _wordTag = RegExp(r'\((\d+),(\d+),\d+\)');

// `List.sort` 不稳定，时间相同的行要靠下标保持原顺序。
List<LyricLine> _byTime(Iterable<LyricLine> lines) {
  final indexed = [
    for (final (index, line) in lines.indexed) (index: index, line: line),
  ];
  indexed.sort((a, b) {
    final byTime = a.line.timeMs.compareTo(b.line.timeMs);
    return byTime == 0 ? a.index.compareTo(b.index) : byTime;
  });
  return [for (final entry in indexed) entry.line];
}

List<LyricLine> parseLrc(String lrc) {
  final found = <LyricLine>[];
  for (final row in lrc.split('\n')) {
    final tags = _timeTag.allMatches(row).toList(growable: false);
    if (tags.isEmpty) continue;
    final text = row.replaceAll(_timeTag, '').trim();
    for (final tag in tags) {
      final minutes = int.parse(tag.group(1)!);
      final seconds = int.parse(tag.group(2)!);
      final fraction = (tag.group(3) ?? '').padRight(3, '0');
      final milliseconds = fraction.isEmpty ? 0 : int.parse(fraction);
      found.add(
        LyricLine(
          timeMs: minutes * 60000 + seconds * 1000 + milliseconds,
          text: text,
        ),
      );
    }
  }
  final lines = _byTime(found);
  return lines
      .asMap()
      .entries
      .where(
        (entry) =>
            entry.value.text.isNotEmpty ||
            entry.key == 0 ||
            lines[entry.key - 1].text.isNotEmpty,
      )
      .map((entry) => entry.value)
      .toList(growable: false);
}

/// 歌词来自服务端转存的第三方数据，读不出来的行直接跳过。
List<LyricLine> parseWordLyrics(String source) {
  final found = <LyricLine>[];
  for (final row in source.split(RegExp(r'\r?\n'))) {
    final line = _parseWordLine(row);
    if (line != null) found.add(line);
  }
  final lines = _byTime(found);
  final result = <LyricLine>[];
  for (final (index, line) in lines.indexed) {
    result.add(line);
    final next = index + 1 < lines.length ? lines[index + 1] : null;
    if (next == null || next.timeMs - line.endMs! >= interludeGapMs) {
      result.add(LyricLine(timeMs: line.endMs!, text: ''));
    }
  }
  return result;
}

LyricLine? _parseWordLine(String row) {
  final head = _wordLineHead.firstMatch(row);
  if (head == null) return null;
  final timeMs = _readMs(head.group(1)!);
  final durationMs = _readMs(head.group(2)!);
  if (timeMs == null || durationMs == null) return null;
  final tags = _wordTag.allMatches(row).toList(growable: false);
  final words = <LyricWord>[];
  for (final (index, tag) in tags.indexed) {
    final end = index + 1 < tags.length ? tags[index + 1].start : row.length;
    final text = row.substring(tag.end, end);
    final startMs = _readMs(tag.group(1)!);
    final length = _readMs(tag.group(2)!);
    if (startMs == null || length == null) return null;
    if (text.trim().isNotEmpty) {
      words.add(LyricWord(startMs: startMs, durationMs: length, text: text));
    } else if (words.isNotEmpty) {
      // 字各自绘制：只含空格的字单独成字时，两侧的空格不会合并，词间距会变成两倍。
      final last = words.removeLast();
      words.add(
        LyricWord(
          startMs: last.startMs,
          durationMs: last.durationMs,
          text: last.text + text,
        ),
      );
    }
  }
  if (words.isEmpty) return null;
  _trimAt(words, 0, (text) => text.trimLeft());
  _trimAt(words, words.length - 1, (text) => text.trimRight());
  return LyricLine(
    timeMs: timeMs,
    endMs: timeMs + durationMs,
    text: words.map((word) => word.text).join(),
    words: List.unmodifiable(words),
  );
}

int? _readMs(String digits) {
  final value = int.tryParse(digits);
  return value == null || value > _longestLyricMs ? null : value;
}

void _trimAt(
  List<LyricWord> words,
  int index,
  String Function(String text) trim,
) {
  final word = words[index];
  words[index] = LyricWord(
    startMs: word.startMs,
    durationMs: word.durationMs,
    text: trim(word.text),
  );
}

/// 由翻译找行，而不是由行找翻译：否则没有翻译的行会借用相邻行的翻译。
List<LyricLine> pairTranslations(
  List<LyricLine> lines,
  List<LyricLine> translations,
) {
  final sung = [
    for (final (index, line) in lines.indexed)
      if (!line.isBlank) (index: index, line: line),
  ];
  final sungLines = [for (final entry in sung) entry.line];
  final nearest = <int, LyricLine>{};
  for (final translation in translations) {
    if (translation.isBlank || sung.isEmpty) continue;
    final found = lineIndexAt(sungLines, translation.timeMs);
    var before = found < 0 ? 0 : found;
    while (before > 0 &&
        sungLines[before - 1].timeMs == sungLines[before].timeMs) {
      before--;
    }
    final after = found + 1 < sung.length ? found + 1 : found;
    int gap(int index) => (sung[index].line.timeMs - translation.timeMs).abs();
    final chosen = gap(after) < gap(before) ? after : before;
    if (gap(chosen) > maxTranslationGapMs) continue;
    final line = sung[chosen];
    final current = nearest[line.index];
    if (current == null ||
        gap(chosen) < (line.line.timeMs - current.timeMs).abs()) {
      nearest[line.index] = translation;
    }
  }
  return [
    for (final (index, line) in lines.indexed)
      if (nearest[index] case final translation?)
        line._withTranslation(translation.text)
      else
        line,
  ];
}

List<LyricLine> buildLyricLines({
  required String lyric,
  String? words,
  String? translation,
}) {
  final wordLines = parseWordLyrics(words ?? '');
  final lines = pairTranslations(
    wordLines.isNotEmpty ? wordLines : parseLrc(lyric),
    parseLrc(translation ?? ''),
  );
  for (final line in lines) {
    if (line.isBlank) continue;
    if (line.timeMs < lyricBreakMinimumMs) return lines;
    return [const LyricLine(timeMs: 0, text: ''), ...lines];
  }
  return lines;
}

int lineIndexAt(List<LyricLine> lines, int positionMs) {
  var low = 0;
  var high = lines.length - 1;
  var found = -1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    if (lines[middle].timeMs <= positionMs) {
      found = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return found;
}
