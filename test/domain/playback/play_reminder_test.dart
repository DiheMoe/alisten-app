import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/playback/play_reminder.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:flutter_test/flutter_test.dart';

import '../room/room_fixtures.dart';

void main() {
  bool remind({
    bool enabled = true,
    bool live = true,
    String? requestedBy = 'me',
    String? previousEntryId = 'previous',
    int? firstSeenAtMs = 1000,
    int nowMs = 31000,
  }) {
    return shouldRemind(
      enabled: enabled,
      live: live,
      requestedByMemberId: requestedBy,
      currentMemberId: 'me',
      previousEntryId: previousEntryId,
      nextEntryId: 'next',
      firstSeenAtMs: firstSeenAtMs,
      nowMs: nowMs,
    );
  }

  test('reminds only after waiting at least thirty seconds for a live own-track update', () {
    expect(remind(nowMs: 30999), isFalse);
    expect(remind(nowMs: 31000), isTrue);
    expect(remind(live: false), isFalse);
    expect(remind(enabled: false), isFalse);
  });

  test('does not remind for others auto entries repeats or unseen entries', () {
    expect(remind(requestedBy: 'other'), isFalse);
    expect(remind(requestedBy: null), isFalse);
    expect(remind(previousEntryId: 'next'), isFalse);
    expect(remind(firstSeenAtMs: null), isFalse);
  });

  test('the wait of an own entry counts from when it was first seen, across '
      'the gap without a track while it is prepared', () {
    final tracker = PlayReminderTracker();
    final other = _entry('other-entry', testMember);
    final own = _entry('own-entry', _me);
    QueueEntry? observe(RoomSnapshot snapshot, {required int at}) {
      return tracker.observe(
        snapshot: snapshot,
        memberId: _me.id,
        live: true,
        enabled: true,
        nowMs: at,
      );
    }

    expect(observe(_snapshot(playing: other, items: [own]), at: 0), isNull);
    // 上一首放完了，下一首正在准备。
    expect(observe(_snapshot(pending: own), at: 40000), isNull);
    // 服务端在条目开始播放之前把它移出队列。
    expect(observe(_snapshot(), at: 41000), isNull);

    expect(observe(_snapshot(playing: own), at: 42000), same(own));
  });
}

const _me = Member(id: 'me', name: '我', avatarHash: 'hash');

QueueEntry _entry(String id, Member by) {
  return QueueEntry(
    id: id,
    track: testTrack,
    meta: testTrackMeta,
    requestedBy: by,
    auto: false,
    likes: 0,
    status: QueueEntryStatus.ready,
  );
}

RoomSnapshot _snapshot({
  QueueEntry? playing,
  QueueEntry? pending,
  List<QueueEntry> items = const [],
}) {
  final base = testRoomSnapshot();
  return RoomSnapshot(
    term: base.term,
    seq: base.seq,
    room: base.room,
    playMode: base.playMode,
    nowPlaying: playing == null
        ? null
        : NowPlaying(
            entry: playing,
            mediaUrl: '/media/netease/track-id',
            startedAtMs: 42000,
            durationMs: 180000,
            gain: 1,
            lyric: '',
          ),
    pending: pending,
    items: items,
    members: base.members,
    onlineCount: base.onlineCount,
  );
}
