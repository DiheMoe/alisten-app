const _staleSampleMs = 500;
const _seekForwardMs = 1000;

final class LyricSample {
  const LyricSample(this.positionMs, {required this.jumped});

  final int positionMs;
  final bool jumped;
}

/// 播放器的位置更新事件可能比外推值略旧，不能让点亮的边往回退。
final class LyricClock {
  int _lastMs = 0;

  LyricSample advance(int sampleMs) {
    final last = _lastMs;
    final jumped =
        sampleMs < last - _staleSampleMs || sampleMs > last + _seekForwardMs;
    final positionMs = !jumped && sampleMs < last ? last : sampleMs;
    _lastMs = positionMs;
    return LyricSample(positionMs, jumped: jumped);
  }

  void startAt(int positionMs) => _lastMs = positionMs;
}
