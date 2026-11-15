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
        'items': <Object?>[],
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
          },
          'playMode': 'sequential',
          'nowPlaying': null,
          'pending': null,
          'next': next,
          'items': <Object?>[],
          'members': {'sessions': <Object?>[], 'onlineCount': 0},
        }),
      );

      expect(event, isA<QueueUpdatedEvent>());
      expect(snapshot.room.id, 'room-id');
    }
  });
}
