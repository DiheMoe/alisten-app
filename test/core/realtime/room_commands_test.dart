import 'package:alisten/core/clock/server_clock.dart';
import 'package:alisten/core/protocol/protocol.gen.dart' as protocol;
import 'package:alisten/core/realtime/room_commands.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _RecordingTransport transport;
  late RoomCommands commands;

  setUp(() {
    transport = _RecordingTransport();
    commands = RoomCommands(transport);
  });

  test('sync sends room.sync and decodes the domain snapshot', () async {
    transport.response = {'room': _snapshotJson()};

    final snapshot = await commands.sync();

    expect(transport.sent.single.type, protocol.RoomRequestTypes.roomSync);
    expect(
      transport.sent.single.data,
      const protocol.RoomSyncRequest().toJson(),
    );
    expect(snapshot.room.id, 'room-id');
    expect(snapshot.playMode, RoomPlayMode.random);
    expect(snapshot.nowPlaying!.entry.id, 'entry-id');
    expect(snapshot.members.single.id, 'member-id');
  });

  test(
    'addTrack sends queue.add with the track and returns the entry',
    () async {
      transport.response = {'entry': _entryJson()};

      final entry = await commands.addTrack(
        const Track(source: TrackSource.qq, id: 'song'),
      );

      expect(transport.sent.single.type, protocol.RoomRequestTypes.queueAdd);
      expect(
        transport.sent.single.data,
        const protocol.QueueAddRequest(
          track: protocol.Track(source: protocol.Source.qq, id: 'song'),
        ).toJson(),
      );
      expect(entry.id, 'entry-id');
      expect(entry.track.source, TrackSource.netease);
      expect(entry.requestedBy!.name, '听众');
    },
  );

  test('removeEntry sends queue.remove', () async {
    await commands.removeEntry('entry-id');

    expect(transport.sent.single.type, protocol.RoomRequestTypes.queueRemove);
    expect(
      transport.sent.single.data,
      const protocol.QueueRemoveRequest(entryId: 'entry-id').toJson(),
    );
  });

  test('likeEntry sends queue.like and returns the like count', () async {
    transport.response = {'likes': 4};

    final likes = await commands.likeEntry('entry-id');

    expect(transport.sent.single.type, protocol.RoomRequestTypes.queueLike);
    expect(
      transport.sent.single.data,
      const protocol.QueueLikeRequest(entryId: 'entry-id').toJson(),
    );
    expect(likes, 4);
  });

  test('voteSkip sends playback.voteSkip and returns the tally', () async {
    transport.response = {'votes': 2, 'required': 3, 'skipped': false};

    final result = await commands.voteSkip();

    expect(
      transport.sent.single.type,
      protocol.RoomRequestTypes.playbackVoteSkip,
    );
    expect(
      transport.sent.single.data,
      const protocol.PlaybackVoteSkipRequest().toJson(),
    );
    expect(result.votes, 2);
    expect(result.requiredVotes, 3);
    expect(result.skipped, isFalse);
  });

  test('setPlayMode sends settings.setPlayMode with the wire mode', () async {
    await commands.setPlayMode(RoomPlayMode.rotation);

    expect(
      transport.sent.single.type,
      protocol.RoomRequestTypes.settingsSetPlayMode,
    );
    expect(
      transport.sent.single.data,
      const protocol.SettingsSetPlayModeRequest(
        playMode: protocol.PlayMode.rotation,
      ).toJson(),
    );
  });

  test('sendChat sends chat.send', () async {
    await commands.sendChat('你好');

    expect(transport.sent.single.type, protocol.RoomRequestTypes.chatSend);
    expect(
      transport.sent.single.data,
      const protocol.ChatSendRequest(content: '你好').toJson(),
    );
  });

  test('searchTracks sends search.tracks and returns one page', () async {
    transport.response = {
      'items': [_trackSummaryJson()],
      'total': 41,
    };

    final page = await commands.searchTracks(
      source: TrackSource.bilibili,
      keyword: '晴天',
      page: 2,
    );

    expect(transport.sent.single.type, protocol.RoomRequestTypes.searchTracks);
    expect(
      transport.sent.single.data,
      const protocol.SearchTracksRequest(
        source: protocol.Source.bilibili,
        keyword: '晴天',
        page: 2,
        pageSize: 20,
      ).toJson(),
    );
    expect(page.total, 41);
    expect(page.items.single.meta.title, '歌曲');
  });

  test('searchPlaylists sends search.playlists and returns one page', () async {
    transport.response = {
      'items': [_playlistJson()],
      'total': 1,
    };

    final page = await commands.searchPlaylists(
      source: TrackSource.netease,
      keyword: '夏天',
      page: 1,
      pageSize: 10,
    );

    expect(
      transport.sent.single.type,
      protocol.RoomRequestTypes.searchPlaylists,
    );
    expect(
      transport.sent.single.data,
      const protocol.SearchPlaylistsRequest(
        source: protocol.Source.netease,
        keyword: '夏天',
        page: 1,
        pageSize: 10,
      ).toJson(),
    );
    expect(page.total, 1);
    expect(page.items.single.source, TrackSource.netease);
    expect(page.items.single.trackCount, 12);
  });

  test('playlistTracks sends playlist.tracks and returns its tracks', () async {
    transport.response = {
      'items': [_trackSummaryJson()],
      'total': 1,
    };

    final tracks = await commands.playlistTracks(
      source: TrackSource.netease,
      playlistId: 'list-id',
    );

    expect(
      transport.sent.single.type,
      protocol.RoomRequestTypes.playlistTracks,
    );
    expect(
      transport.sent.single.data,
      const protocol.PlaylistTracksRequest(
        source: protocol.Source.netease,
        playlistId: 'list-id',
      ).toJson(),
    );
    expect(tracks.single.track.id, 'track-id');
  });

  test('recommendations sends recommend.list and returns its tracks', () async {
    transport.response = {
      'items': [_trackSummaryJson()],
    };

    final tracks = await commands.recommendations();

    expect(transport.sent.single.type, protocol.RoomRequestTypes.recommendList);
    expect(
      transport.sent.single.data,
      const protocol.RecommendListRequest().toJson(),
    );
    expect(tracks.single.meta.artist, '歌手');
  });

  test(
    'an undecodable success fails a read and leaves a mutation unknown',
    () async {
      transport.response = {'items': 'not a list', 'total': 1};
      await expectLater(
        commands.searchTracks(
          source: TrackSource.netease,
          keyword: 'x',
          page: 1,
        ),
        throwsA(
          isA<RoomRequestException>()
              .having((error) => error.code, 'code', 'PROTOCOL_MISMATCH')
              .having(
                (error) => error.outcome,
                'outcome',
                RoomRequestOutcome.failed,
              ),
        ),
      );

      transport.response = {'likes': 'many'};
      await expectLater(
        commands.likeEntry('entry-id'),
        throwsA(
          isA<RoomRequestException>()
              .having((error) => error.code, 'code', 'PROTOCOL_MISMATCH')
              .having(
                (error) => error.outcome,
                'outcome',
                RoomRequestOutcome.unknown,
              ),
        ),
      );
    },
  );
}

final class _RecordingTransport implements RoomTransport {
  final List<({String type, Map<String, Object?> data})> sent = [];
  Map<String, Object?> response = const {};

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> data,
  ) async {
    sent.add((type: type, data: data));
    return response;
  }

  @override
  Stream<RoomTransportEvent> get events => const Stream.empty();

  @override
  ServerClock get clock => ServerClock(now: () => 0);

  @override
  Future<void> start() async {}

  @override
  void check() {}

  @override
  void probe(Duration deadline) {}

  @override
  void restart() {}

  @override
  Future<void> stop() async {}
}

Map<String, Object?> _memberJson() {
  return {'id': 'member-id', 'name': '听众', 'avatarHash': 'hash'};
}

Map<String, Object?> _trackMetaJson() {
  return {
    'title': '歌曲',
    'artist': '歌手',
    'album': '专辑',
    'coverUrl': 'https://example.com/cover.jpg',
    'pageUrl': 'https://example.com/track',
    'durationMs': 180000,
  };
}

Map<String, Object?> _trackSummaryJson() {
  return {
    'track': {'source': 'netease', 'id': 'track-id'},
    'meta': _trackMetaJson(),
  };
}

Map<String, Object?> _playlistJson() {
  return {
    'source': 'netease',
    'id': 'list-id',
    'name': '夏日歌单',
    'coverUrl': 'https://example.com/list.jpg',
    'creator': '创建者',
    'description': '描述',
    'trackCount': 12,
    'playCount': 300,
  };
}

Map<String, Object?> _entryJson() {
  return {
    'id': 'entry-id',
    'track': {'source': 'netease', 'id': 'track-id'},
    'meta': _trackMetaJson(),
    'by': _memberJson(),
    'auto': false,
    'likes': 0,
    'status': 'ready',
  };
}

Map<String, Object?> _snapshotJson() {
  return {
    'term': 1,
    'seq': 1,
    'room': {
      'id': 'room-id',
      'name': '房间',
      'description': '描述',
      'kind': 'ephemeral',
    },
    'playMode': 'random',
    'nowPlaying': {
      'entry': _entryJson(),
      'mediaUrl': '/media/netease/track-id',
      'startedAtMs': 1000000,
      'durationMs': 180000,
      'gain': 1.0,
      'lyric': '',
    },
    'pending': null,
    'items': [_entryJson()],
    'members': {
      'sessions': [_memberJson()],
      'onlineCount': 1,
    },
  };
}
