import 'dart:convert';
import 'dart:io';

import 'package:alisten/core/protocol/domain_mapper.dart';
import 'package:alisten/core/protocol/http.gen.dart' as http;
import 'package:alisten/core/protocol/protocol.gen.dart' as protocol;
import 'package:alisten/domain/member/member.dart' as domain_member;
import 'package:alisten/domain/room/room.dart' as domain_room;
import 'package:alisten/domain/track/track.dart' as domain_track;
import 'package:flutter_test/flutter_test.dart';

// 与后端交叉核对的测试要求后端仓库与本仓库并列检出；CI 不检出后端，因此跳过。
const _backendIdlPath = '../alisten/protocol/idl.json';
const _backendTypesPath = '../alisten/protocol/types.gen.go';
final _backendSkip = Directory('../alisten/protocol').existsSync()
    ? null
    : 'needs the backend checked out at ../alisten';

void main() {
  group('generated protocol', () {
    test('version equals the Go constant generated from the same IDL', () {
      final goVersion = RegExp(r'const Version = "(\w+)"')
          .firstMatch(File(_backendTypesPath).readAsStringSync())
          ?.group(1);

      expect(goVersion, isNotNull);
      expect(protocol.protocolVersion, goVersion);
    }, skip: _backendSkip);

    test('a track without word timings keeps both lyric fields absent', () {
      final nowPlaying = toDomainNowPlaying(
        protocol.NowPlaying.fromJson(_nowPlayingPayload()),
      );

      expect(nowPlaying.lyricWords, isNull);
      expect(nowPlaying.lyricTrans, isNull);
    });

    test('word timings and translations reach the domain unchanged', () {
      final nowPlaying = toDomainNowPlaying(
        protocol.NowPlaying.fromJson({
          ..._nowPlayingPayload(),
          'lyricWords': '[1000,900](1000,400,0)故(1400,500,0)事',
          'lyricTrans': '[00:01.00]Story',
        }),
      );

      expect(nowPlaying.lyricWords, '[1000,900](1000,400,0)故(1400,500,0)事');
      expect(nowPlaying.lyricTrans, '[00:01.00]Story');
    });

    test('DTO round trip keeps required nullable fields explicit', () {
      final payload = _entryPayload(by: null);

      final entry = protocol.Entry.fromJson(payload);

      expect(entry.by, isNull);
      expect(entry.track.source, protocol.Source.netease);
      expect(entry.meta.durationMs, 183000);
      expect(entry.toJson(), payload);
      expect(entry.toJson(), containsPair('by', null));
    });

    test('responses ignore fields added by a newer server', () {
      final listing = protocol.RoomListing.fromJson(<String, Object?>{
        ..._roomListingPayload(),
        'futureField': 1,
      });
      final entry = protocol.Entry.fromJson(<String, Object?>{
        ..._entryPayload(by: null),
        'meta': <String, Object?>{
          ...(_entryPayload(by: null)['meta']! as Map<String, Object?>),
          'futureMeta': <String, Object?>{'nested': true},
        },
      });

      expect(listing.id, 'room-1');
      expect(listing.slug, isNull);
      expect(listing.toJson(), isNot(contains('futureField')));
      expect(entry.meta.title, 'Song');
    });

    test('responses are not held to request-side value constraints', () {
      final link = protocol.Track.fromJson(<String, Object?>{
        'source': 'link',
        'id': 'not a url',
      });
      final bilibili = protocol.Track.fromJson(<String, Object?>{
        'source': 'bilibili',
        'id': 'not-a-bvid',
      });
      final member = protocol.Member.fromJson(<String, Object?>{
        'id': 'member-1',
        'name': 'nul\u0000name',
        'avatarHash': '',
      });

      expect(link.id, 'not a url');
      expect(bilibili.id, 'not-a-bvid');
      expect(member.name, 'nul\u0000name');
    });

    test('unknown enum values are protocol mismatches', () {
      Object? caught;
      try {
        protocol.Track.fromJson(<String, Object?>{
          'source': 'youtube',
          'id': '1',
        });
      } on FormatException catch (error) {
        caught = error;
      }

      expect(caught, isA<protocol.ProtocolMismatchException>());
      expect(
        () => protocol.RoomListing.fromJson(<String, Object?>{
          ..._roomListingPayload(),
          'kind': 'temporary',
        }),
        throwsA(isA<protocol.ProtocolMismatchException>()),
      );
    });

    test('decoding still checks presence, null, and JSON types', () {
      final payload = _entryPayload(by: null);

      for (final invalid in <Map<String, Object?>>[
        _without(payload, 'by'),
        <String, Object?>{...payload, 'likes': '2'},
        <String, Object?>{...payload, 'id': null},
        <String, Object?>{...payload, 'track': 'netease:123'},
      ]) {
        expect(
          () => protocol.Entry.fromJson(invalid),
          throwsA(
            allOf(
              isA<FormatException>(),
              isNot(isA<protocol.ProtocolMismatchException>()),
            ),
          ),
          reason: '$invalid',
        );
      }
      expect(
        () => protocol.RoomActivity.fromJson(<String, Object?>{
          'kind': 'voted',
          'message': 'voted',
          'votes': null,
        }),
        throwsFormatException,
      );
    });

    test('queue-add requests assert exactly one oneOf alternative', () {
      final track = protocol.Track.fromJson(<String, Object?>{
        'source': 'qq',
        'id': '42',
      });
      final source = protocol.Source.fromJson('qq');

      expect(
        protocol.QueueAddRequest(track: track, requester: 'bot').toJson(),
        <String, Object?>{
          'track': <String, Object?>{'source': 'qq', 'id': '42'},
          'requester': 'bot',
        },
      );
      expect(
        protocol.QueueAddRequest(source: source, keyword: 'hello').toJson(),
        <String, Object?>{'source': 'qq', 'keyword': 'hello'},
      );
      expect(protocol.QueueAddRequest.new, throwsA(isA<AssertionError>()));
      expect(
        () => protocol.QueueAddRequest(source: source),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => protocol.QueueAddRequest(
          track: track,
          source: source,
          keyword: 'hello',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('reserved JSON property names retain their wire representation', () {
      final activity = protocol.RoomActivity.fromJson(<String, Object?>{
        'kind': 'voted',
        'message': 'voted',
        'votes': 1,
        'required': 2,
      });

      expect(activity.requiredValue, 2);
      expect(activity.toJson()['required'], 2);
    });

    test('message type constants list every IDL request and event type', () {
      final idl = jsonDecode(
        File(_backendIdlPath).readAsStringSync(),
      ) as Map<String, dynamic>;
      List<String> types(String section) => <String>[
        for (final item in idl[section] as List<dynamic>)
          (item as Map<String, dynamic>)['type'] as String,
      ];

      expect(protocol.RoomRequestTypes.values, types('x-requests'));
      expect(protocol.RoomEventTypes.values, types('x-events'));
      expect(protocol.RoomRequestTypes.queueAdd, 'queue.add');
      expect(protocol.RoomRequestTypes.playbackVoteSkip, 'playback.voteSkip');
      expect(protocol.RoomEventTypes.playbackUpdated, 'playback.updated');
      expect(protocol.RoomEventTypes.roomActivity, 'room.activity');
    }, skip: _backendSkip);

    test('site admin DTOs keep their wire representation', () {
      expect(
        protocol.APIKey.fromJson(<String, Object?>{'key': 'k-1'}).key,
        'k-1',
      );
      expect(
        protocol.QRLogin.fromJson(<String, Object?>{
          'key': 'abc',
          'qrImage': 'data:image/png;base64,AA==',
          'expiresAtMs': 1700000000000,
        }).expiresAtMs,
        1700000000000,
      );
      expect(
        protocol.QRLoginResult.fromJson(<String, Object?>{
          'status': 'scanned',
          'message': '',
        }).status,
        protocol.QRLoginStatus.scanned,
      );
      final account = protocol.SourceAccount.fromJson(<String, Object?>{
        'id': '42',
        'name': null,
        'vip': null,
        'verified': false,
      });
      expect(account.name, isNull);
      expect(account.vip, isNull);
      expect(
        const protocol.AdminUpdateRoomRequest(slug: '', password: '').toJson(),
        <String, Object?>{'password': '', 'slug': ''},
      );
      expect(
        const protocol.AdminStartQqLoginRequest(type: protocol.QQLoginType.wx)
            .toJson(),
        <String, Object?>{'type': 'wx'},
      );
    });

    test('generated close codes preserve protocol values', () {
      expect(protocol.WsCloseCodes.invalidArgument, 1008);
      expect(protocol.WsCloseCodes.serviceRestart, 1012);
      expect(protocol.WsCloseCodes.unauthorized, 4401);
      expect(protocol.WsCloseCodes.notFound, 4404);
      expect(protocol.WsCloseCodes.handshakeTimeout, 4408);
      expect(protocol.WsCloseCodes.clientOutdated, 4426);
    });
  });

  group('REST descriptors', () {
    test('only the site admin API requires the admin token', () {
      expect(
        http.RestEndpoints.values
            .where((endpoint) => endpoint.auth == http.HttpAuth.admin)
            .map((endpoint) => endpoint.name),
        unorderedEquals(
          http.RestEndpoints.values
              .where((endpoint) => endpoint.path.startsWith('/api/admin/'))
              .map((endpoint) => endpoint.name),
        ),
      );
      expect(
        http.RestEndpoints.values.where(
          (endpoint) => endpoint.auth == http.HttpAuth.admin,
        ),
        hasLength(21),
      );
      expect(http.RestEndpoints.adminListRooms.path, '/api/admin/rooms');
      expect(http.RestEndpoints.roomSync.name, 'roomSync');
      expect(http.RestEndpoints.roomSync.auth, http.HttpAuth.ticket);
      expect(http.RestEndpoints.createMember.auth, http.HttpAuth.none);
      expect(http.RestEndpoints.getMe.auth, http.HttpAuth.member);
      expect(http.RestEndpoints.queueAdd.successStatus, 201);
      expect(http.RestEndpoints.queueAdd.hasLocation, isTrue);
      expect(
        http.RestEndpoints.values.map((endpoint) => endpoint.name).toSet(),
        hasLength(http.RestEndpoints.values.length),
      );
    });

    test(
      'path descriptors encode parameters and reject wrong parameter sets',
      () {
        const getRoom = http.RestEndpoints.getRoom;
        const playlistTracks = http.RestEndpoints.playlistTracks;

        expect(getRoom.pathParameters, <String>['ref']);
        expect(
          getRoom.buildPath(<String, String>{'ref': 'room alias'}),
          '/api/rooms/room%20alias',
        );
        expect(
          playlistTracks.buildPath(<String, String>{
            'source': 'qq',
            'playlistId': 'a/b',
          }),
          '/api/room/playlists/qq/a%2Fb/tracks',
        );
        expect(
          () => getRoom.buildPath(<String, String>{}),
          throwsArgumentError,
        );
        expect(
          () => getRoom.buildPath(<String, String>{'ref': 'x', 'extra': 'y'}),
          throwsArgumentError,
        );
      },
    );
  });

  test('pure domain models represent snapshots and room events', () {
    const track = domain_track.Track(
      source: domain_track.TrackSource.link,
      id: 'https://example.com/song',
    );
    const meta = domain_track.TrackMeta(
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      coverUrl: 'https://example.com/cover',
      pageUrl: 'https://example.com/song',
      durationMs: 1000,
    );
    const member = domain_member.Member(
      id: 'member-1',
      name: 'Listener',
      avatarHash: '',
    );
    const entry = domain_room.QueueEntry(
      id: 'entry-1',
      track: track,
      meta: meta,
      requestedBy: member,
      auto: false,
      likes: 0,
      status: domain_room.QueueEntryStatus.ready,
    );
    const nowPlaying = domain_room.NowPlaying(
      entry: entry,
      mediaUrl: '/api/media/1',
      startedAtMs: 100,
      durationMs: 1000,
      gain: 0.8,
      lyric: '',
    );
    const snapshot = domain_room.RoomSnapshot(
      term: 1,
      seq: 2,
      room: domain_room.RoomInfo(
        id: 'room-1',
        name: 'Room',
        description: '',
        kind: domain_room.RoomKind.ephemeral,
      ),
      playMode: domain_room.RoomPlayMode.sequential,
      nowPlaying: nowPlaying,
      pending: null,
      items: <domain_room.QueueEntry>[entry],
      members: <domain_member.Member>[member],
      onlineCount: 1,
    );
    const event = domain_room.PlaybackUpdatedEvent(
      term: 1,
      seq: 3,
      nowPlaying: null,
    );

    expect(snapshot.nowPlaying?.entry.track, same(track));
    expect(snapshot.members.single, same(member));
    expect(event, isA<domain_room.RoomEvent>());
    expect(event.term, 1);
    expect(event.seq, 3);
  });
}

Map<String, Object?> _nowPlayingPayload() {
  return <String, Object?>{
    'entry': _entryPayload(by: null),
    'mediaUrl': '/media/netease/123',
    'startedAtMs': 1000,
    'durationMs': 180000,
    'gain': 1,
    'lyric': '[00:01.00]故事',
  };
}

Map<String, Object?> _entryPayload({required Object? by}) {
  return <String, Object?>{
    'id': 'entry-1',
    'track': <String, Object?>{'source': 'netease', 'id': '123'},
    'meta': <String, Object?>{
      'title': 'Song',
      'artist': 'Artist',
      'album': 'Album',
      'coverUrl': 'https://example.com/cover',
      'pageUrl': 'https://example.com/song',
      'durationMs': 183000,
    },
    'by': by,
    'auto': false,
    'likes': 2,
    'status': 'ready',
  };
}

Map<String, Object?> _roomListingPayload() {
  return <String, Object?>{
    'id': 'room-1',
    'slug': null,
    'name': 'Room',
    'description': '',
    'kind': 'ephemeral',
    'hasPassword': false,
    'onlineCount': 3,
  };
}

Map<String, Object?> _without(Map<String, Object?> json, String key) {
  return <String, Object?>{...json}..remove(key);
}
