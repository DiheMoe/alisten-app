final class LyricLine {
  const LyricLine({required this.timeMs, required this.text});

  final int timeMs;
  final String text;
}

final _timeTag = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');

List<LyricLine> parseLrc(String lrc) {
  final indexed = <({int index, LyricLine line})>[];
  for (final row in lrc.split('\n')) {
    final tags = _timeTag.allMatches(row).toList(growable: false);
    if (tags.isEmpty) continue;
    final text = row.replaceAll(_timeTag, '').trim();
    for (final tag in tags) {
      final minutes = int.parse(tag.group(1)!);
      final seconds = int.parse(tag.group(2)!);
      final fraction = (tag.group(3) ?? '').padRight(3, '0');
      final milliseconds = fraction.isEmpty ? 0 : int.parse(fraction);
      indexed.add((
        index: indexed.length,
        line: LyricLine(
          timeMs: minutes * 60000 + seconds * 1000 + milliseconds,
          text: text,
        ),
      ));
    }
  }
  indexed.sort((a, b) {
    final byTime = a.line.timeMs.compareTo(b.line.timeMs);
    return byTime == 0 ? a.index.compareTo(b.index) : byTime;
  });
  final lines = indexed.map((entry) => entry.line).toList(growable: false);
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
