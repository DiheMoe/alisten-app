/// 基于单调的本地时钟，用 ping 往返估计服务端时间。
///
/// 当前 [generation] 的第一个 ping 回复到达之前，用临时样本（来自握手，
/// 或 [reset] 时保留的样本）估计。
final class ServerClock {
  ServerClock({int Function()? now})
    : _now = now ?? _monotonicEpochMilliseconds;

  // 时钟偏移会缓慢漂移，也会随网络路径变化而跳变，所以往返更短
  // 并不能让旧样本更可信。窗口按单调时钟计算，而单调时钟在设备休眠时停止，
  // 窗口察觉不到休眠；休眠后由所有者重置时钟。
  static const _windowMs = 15000;

  final int Function() _now;
  final List<_ClockSample> _samples = [];
  int _generation = 0;

  int get generation => _generation;

  int now() => _now();

  /// 开始新的估计（如应用回到前台），此前发出的 ping 的回复一律忽略。
  /// 当前最佳样本保留为临时样本，在新一代的第一个回复取代它之前，
  /// [serverNow] 仍有值；设备休眠过时，这个值会落后休眠的时长。
  void reset() {
    _generation++;
    final kept = _best(_now());
    _samples.clear();
    if (kept != null) _samples.add(kept.asProvisional());
  }

  void addSample(
    int sentAt,
    int receivedAt,
    int serverTimeMs, {
    int? generation,
  }) {
    if (generation != null && generation != _generation) return;
    _samples
      ..removeWhere(
        (sample) =>
            sample.provisional || receivedAt - sample.receivedAt > _windowMs,
      )
      ..add(_ClockSample(sentAt, receivedAt, serverTimeMs, provisional: false));
  }

  /// 粗略样本（如握手回复，其中的服务端时间在服务端处理之后读取），
  /// 让 [serverNow] 立即有值。第一个正式样本会取代它；已有正式样本时忽略。
  void addProvisionalSample(int sentAt, int receivedAt, int serverTimeMs) {
    if (_samples.any((sample) => !sample.provisional)) return;
    _samples
      ..clear()
      ..add(_ClockSample(sentAt, receivedAt, serverTimeMs, provisional: true));
  }

  int? serverNow() {
    final now = _now();
    final best = _best(now);
    return best == null ? null : (now + best.offsetMs).round();
  }

  _ClockSample? _best(int now) {
    _ClockSample? best;
    for (final sample in _samples) {
      if (now - sample.receivedAt > _windowMs) continue;
      if (best == null || sample.roundTripMs < best.roundTripMs) best = sample;
    }
    return best ?? _samples.lastOrNull;
  }
}

final class _ClockSample {
  _ClockSample(
    int sentAt,
    this.receivedAt,
    int serverTimeMs, {
    required this.provisional,
  }) : roundTripMs = receivedAt - sentAt,
       offsetMs = serverTimeMs - (sentAt + receivedAt) / 2;

  const _ClockSample._provisional(
    this.receivedAt,
    this.roundTripMs,
    this.offsetMs,
  ) : provisional = true;

  final int receivedAt;
  final int roundTripMs;
  final double offsetMs;
  final bool provisional;

  _ClockSample asProvisional() {
    return _ClockSample._provisional(receivedAt, roundTripMs, offsetMs);
  }
}

int _monotonicEpochMilliseconds() {
  return _epochAtStart + _stopwatch.elapsedMilliseconds;
}

final _epochAtStart = DateTime.now().millisecondsSinceEpoch;
final _stopwatch = Stopwatch()..start();
