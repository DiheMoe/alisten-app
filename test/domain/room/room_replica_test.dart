import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/room/room_replica.dart';
import 'package:flutter_test/flutter_test.dart';

import 'room_fixtures.dart';

void main() {
  test('replica applies only the next sequence and ignores duplicates and old terms', () {
    final replica = RoomReplica(testRoomSnapshot());

    final applied = replica.receive(
      const SettingsUpdatedEvent(
        term: 1,
        seq: 2,
        playMode: RoomPlayMode.random,
      ),
    );
    final duplicate = replica.receive(
      const SettingsUpdatedEvent(
        term: 1,
        seq: 2,
        playMode: RoomPlayMode.rotation,
      ),
    );
    final oldTerm = replica.receive(
      const SettingsUpdatedEvent(
        term: 0,
        seq: 99,
        playMode: RoomPlayMode.rotation,
      ),
    );

    expect(applied.changed, isTrue);
    expect(duplicate.changed, isFalse);
    expect(oldTerm.changed, isFalse);
    expect(replica.state.playMode, RoomPlayMode.random);
    expect(replica.state.seq, 2);
  });

  test('gap requests sync and state events wait while notices are independently delivered', () {
    final replica = RoomReplica(testRoomSnapshot());
    final gap = replica.receive(
      const PlaybackUpdatedEvent(term: 1, seq: 3, nowPlaying: null),
    );

    expect(gap.syncRequired, isTrue);
    expect(replica.state.nowPlaying, isNotNull);

    final ignoredState = replica.receive(
      const PlaybackUpdatedEvent(term: 1, seq: 4, nowPlaying: null),
    );
    final notice = replica.receive(
      const ChatMessageEvent(
        term: 1,
        seq: 5,
        member: testMember,
        content: '你好',
        sentAtMs: 123,
      ),
    );
    final duplicateNotice = replica.receive(
      const ChatMessageEvent(
        term: 1,
        seq: 5,
        member: testMember,
        content: '你好',
        sentAtMs: 123,
      ),
    );

    expect(ignoredState.changed, isFalse);
    expect(notice.notice, isA<ChatMessageEvent>());
    expect(duplicateNotice.notice, isNull);
  });

  test('snapshot replaces state and rejects older events from its term', () {
    final replica = RoomReplica(testRoomSnapshot());
    replica.receive(
      const PlaybackUpdatedEvent(term: 2, seq: 8, nowPlaying: null),
    );

    replica.applySnapshot(testRoomSnapshot(term: 2, seq: 8));
    final stale = replica.receive(
      const SettingsUpdatedEvent(
        term: 2,
        seq: 7,
        playMode: RoomPlayMode.random,
      ),
    );
    final next = replica.receive(
      const SettingsUpdatedEvent(
        term: 2,
        seq: 9,
        playMode: RoomPlayMode.rotation,
      ),
    );

    expect(stale.changed, isFalse);
    expect(next.changed, isTrue);
    expect(replica.state.playMode, RoomPlayMode.rotation);
    expect(replica.state.term, 2);
  });

  test('sync failure leaves replica usable and a later gap can request another sync', () async {
    final replica = RoomReplica(testRoomSnapshot());

    await expectLater(
      replica.sync(() async => throw const FormatException('unavailable')),
      throwsA(isA<FormatException>()),
    );
    expect(replica.syncing, isFalse);

    final result = replica.receive(
      const PlaybackUpdatedEvent(term: 1, seq: 4, nowPlaying: null),
    );
    expect(result.syncRequired, isTrue);
  });

  test('notices advance the cursor without replacing the snapshot', () {
    final initial = testRoomSnapshot();
    final replica = RoomReplica(initial);

    final chat = replica.receive(
      const ChatMessageEvent(
        term: 1,
        seq: 2,
        member: testMember,
        content: '你好',
        sentAtMs: 123,
      ),
    );
    final next = replica.receive(
      const SettingsUpdatedEvent(
        term: 1,
        seq: 3,
        playMode: RoomPlayMode.random,
      ),
    );

    expect(chat.changed, isFalse);
    expect(chat.syncRequired, isFalse);
    expect(chat.notice, isA<ChatMessageEvent>());
    expect(next.changed, isTrue, reason: 'seq 3 follows the chat at seq 2');
    expect(replica.state.playMode, RoomPlayMode.random);
  });

  test('a notice leaves the snapshot identical', () {
    final initial = testRoomSnapshot();
    final replica = RoomReplica(initial);

    replica.receive(
      const RoomActivityEvent(
        term: 1,
        seq: 2,
        kind: RoomActivityKind.liked,
        message: '点赞',
      ),
    );

    expect(replica.state, same(initial));
  });

  test('an unreadable event requires a sync even at the next position', () {
    final replica = RoomReplica(testRoomSnapshot());

    final result = replica.receive(const UnreadableRoomEvent(term: 1, seq: 2));

    expect(result.syncRequired, isTrue);
    expect(result.changed, isFalse);
  });
}
