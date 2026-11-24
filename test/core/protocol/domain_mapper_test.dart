import 'package:alisten/core/protocol/domain_mapper.dart';
import 'package:alisten/core/protocol/protocol.gen.dart' as protocol;
import 'package:alisten/domain/room/room.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('covers on hosts known to serve HTTPS are upgraded to HTTPS, '
      'other covers are kept', () {
    String cover(String url) {
      return toDomainTrackMeta(
        protocol.TrackMeta(
          album: '',
          artist: '',
          coverUrl: url,
          durationMs: 1,
          pageUrl: '',
          title: '',
        ),
      ).coverUrl;
    }

    expect(
      cover('http://p1.music.126.net/a/1.jpg'),
      'https://p1.music.126.net/a/1.jpg',
    );
    expect(
      cover('http://p4.music.126.net/a/1.jpg?param=300y300'),
      'https://p4.music.126.net/a/1.jpg?param=300y300',
    );
    expect(
      cover('http://y.gtimg.cn/music/1.jpg'),
      'https://y.gtimg.cn/music/1.jpg',
    );
    expect(
      cover('http://i0.hdslb.com/bfs/1.jpg'),
      'https://i0.hdslb.com/bfs/1.jpg',
    );
    expect(
      cover('http://p5.music.126.net/1.jpg'),
      'http://p5.music.126.net/1.jpg',
    );
    expect(cover('http://evilhdslb.com/1.jpg'), 'http://evilhdslb.com/1.jpg');
    expect(cover('http://example.com/1.jpg'), 'http://example.com/1.jpg');
    expect(cover('https://example.com/1.jpg'), 'https://example.com/1.jpg');
    expect(cover(''), '');
  });

  test('the next track that queue updates and snapshots name is accepted, '
      'with or without a time to load it', () {
    for (final loadWithinMs in [60000, null]) {
      final next = <String, Object?>{
        'entryId': 'next-entry',
        'mediaUrl': '/media/qq/next',
        'loadWithinMs': loadWithinMs,
      };

      final event = toDomainEvent(protocol.RoomEventTypes.queueUpdated, 1, 2, {
        'pending': null,
        'next': next,
        'waiting': <Object?>[],
      });
      final snapshot = toDomainSnapshot(
        protocol.RoomSnapshot.fromJson({
          'term': 1,
          'seq': 2,
          'room': {
            'id': 'room-id',
            'name': '房间',
            'description': '',
            'kind': 'ephemeral',
            'capacity': 16,
          },
          'playMode': 'sequential',
          'nowPlaying': null,
          'pending': null,
          'next': next,
          'waiting': <Object?>[],
          'members': {'sessions': <Object?>[], 'onlineCount': 0},
        }),
      );

      final expected = NextTrack(
        entryId: 'next-entry',
        mediaUrl: '/media/qq/next',
        loadWithinMs: loadWithinMs,
      );
      expect((event as QueueUpdatedEvent).next, expected);
      expect(snapshot.next, expected);
    }
  });

  test(
    'room capacities are read from listings, snapshots and room updates',
    () {
      final listing = toDomainRoomListing(
        protocol.RoomListing.fromJson({
          'id': 'room-id',
          'slug': null,
          'name': '房间',
          'description': '',
          'kind': 'persistent',
          'hasPassword': false,
          'onlineCount': 3,
          'capacity': 64,
        }),
      );
      final snapshot = toDomainSnapshot(
        protocol.RoomSnapshot.fromJson({
          'term': 1,
          'seq': 2,
          'room': {
            'id': 'room-id',
            'name': '房间',
            'description': '',
            'kind': 'ephemeral',
            'capacity': 16,
          },
          'playMode': 'sequential',
          'nowPlaying': null,
          'pending': null,
          'next': null,
          'waiting': <Object?>[],
          'members': {'sessions': <Object?>[], 'onlineCount': 0},
        }),
      );
      final updated = toDomainEvent(protocol.RoomEventTypes.roomUpdated, 1, 3, {
        'name': '新名字',
        'description': '新介绍',
        'capacity': 8,
      });

      expect(listing.capacity, 64);
      expect(snapshot.room.capacity, 16);
      expect(
        updated,
        isA<RoomUpdatedEvent>().having((e) => e.capacity, 'capacity', 8),
      );
    },
  );
}
