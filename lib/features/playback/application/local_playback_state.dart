enum LocalPlaybackStatus {
  idle,

  /// 已加载，等待开播时间或服务端时钟。
  waiting,
  loading,
  buffering,
  playing,
  paused,

  /// 曲目时间已走完，房间尚未切到下一首。
  ended,
  error,

  /// 本设备无法播放，不会重试；房间照常可用。
  unavailable,
}

final class LocalPlaybackState {
  const LocalPlaybackState({
    this.status = LocalPlaybackStatus.idle,
    this.positionMs = 0,
    this.durationMs = 0,
    this.volume = 75,
    this.muted = false,
  });

  final LocalPlaybackStatus status;
  final int positionMs;
  final int durationMs;

  /// 0 到 100。
  final int volume;
  final bool muted;

  LocalPlaybackState copyWith({
    LocalPlaybackStatus? status,
    int? positionMs,
    int? durationMs,
    int? volume,
    bool? muted,
  }) {
    return LocalPlaybackState(
      status: status ?? this.status,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LocalPlaybackState &&
        other.status == status &&
        other.positionMs == positionMs &&
        other.durationMs == durationMs &&
        other.volume == volume &&
        other.muted == muted;
  }

  @override
  int get hashCode =>
      Object.hash(status, positionMs, durationMs, volume, muted);
}
