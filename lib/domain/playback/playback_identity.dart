final class PlaybackIdentity {
  const PlaybackIdentity({required this.entryId, required this.startedAtMs});

  final String entryId;
  final int startedAtMs;

  @override
  bool operator ==(Object other) {
    return other is PlaybackIdentity &&
        other.entryId == entryId &&
        other.startedAtMs == startedAtMs;
  }

  @override
  int get hashCode => Object.hash(entryId, startedAtMs);
}
