import 'package:alisten/domain/room/room.dart';

const playReminderDelayMs = 30000;

bool shouldRemind({
  required bool enabled,
  required bool live,
  required String? requestedByMemberId,
  required String currentMemberId,
  required String? previousEntryId,
  required String nextEntryId,
  required int? firstSeenAtMs,
  required int nowMs,
}) {
  if (!enabled || !live) return false;
  if (requestedByMemberId == null || requestedByMemberId != currentMemberId) {
    return false;
  }
  if (previousEntryId == nextEntryId || firstSeenAtMs == null) return false;
  return nowMs - firstSeenAtMs >= playReminderDelayMs;
}

final class PlayReminderTracker {
  final Map<String, int> _firstSeen = {};
  String? _roomId;
  String? _playingEntryId;

  /// 返回刚开播、需要提醒的条目。[live] 表示房间的变化来自实时事件，而不是
  /// 握手或同步。
  QueueEntry? observe({
    required RoomSnapshot? snapshot,
    required String? memberId,
    required bool live,
    required bool enabled,
    required int nowMs,
  }) {
    if (snapshot == null || memberId == null) {
      clear();
      return null;
    }
    if (snapshot.room.id != _roomId) {
      clear();
      _roomId = snapshot.room.id;
    }
    final playing = snapshot.nowPlaying?.entry;
    final remind =
        playing != null &&
        shouldRemind(
          enabled: enabled,
          live: live,
          requestedByMemberId: playing.requestedBy?.id,
          currentMemberId: memberId,
          previousEntryId: _playingEntryId,
          nextEntryId: playing.id,
          firstSeenAtMs: _firstSeen[playing.id],
          nowMs: nowMs,
        );
    final own = {
      for (final entry in [snapshot.pending, ...snapshot.items, playing])
        if (entry != null && entry.requestedBy?.id == memberId) entry.id,
    };
    // 条目开播时先在一个事件中离开队列，下一个事件才开始播放，
    // 所以不切歌的实时事件只添加条目。
    if (!live || playing?.id != _playingEntryId) {
      _firstSeen.removeWhere((id, _) => !own.contains(id));
    }
    for (final id in own) {
      _firstSeen.putIfAbsent(id, () => nowMs);
    }
    _playingEntryId = playing?.id;
    return remind ? playing : null;
  }

  void clear() {
    _firstSeen.clear();
    _roomId = null;
    _playingEntryId = null;
  }
}
