import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';

const testMember = Member(id: 'member-id', name: '听众', avatarHash: 'hash');

const testTrack = Track(source: TrackSource.netease, id: 'track-id');

const testTrackMeta = TrackMeta(
  title: '歌曲',
  artist: '歌手',
  album: '专辑',
  coverUrl: 'https://example.com/cover.jpg',
  pageUrl: 'https://example.com/track',
  durationMs: 180000,
);

const testQueueEntry = QueueEntry(
  id: 'entry-id',
  track: testTrack,
  meta: testTrackMeta,
  requestedBy: testMember,
  auto: false,
  likes: 0,
  status: QueueEntryStatus.ready,
);

const testNowPlaying = NowPlaying(
  entry: testQueueEntry,
  mediaUrl: '/media/netease/track-id',
  startedAtMs: 1000000,
  durationMs: 180000,
  gain: 1,
  lyric: '',
);

RoomSnapshot testRoomSnapshot({int term = 1, int seq = 1}) {
  return RoomSnapshot(
    term: term,
    seq: seq,
    room: const RoomInfo(
      id: 'room-id',
      name: '房间',
      description: '描述',
      kind: RoomKind.ephemeral,
    ),
    playMode: RoomPlayMode.sequential,
    nowPlaying: testNowPlaying,
    pending: null,
    items: const [testQueueEntry],
    members: const [testMember],
    onlineCount: 1,
  );
}
