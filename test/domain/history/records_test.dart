import 'dart:convert';

import 'package:alisten/domain/history/play_record.dart';
import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:flutter_test/flutter_test.dart';

import '../room/room_fixtures.dart';

void main() {
  test(
    'play history deduplicates per room source and id with most recent first',
    () {
      final first = playRecord('same', playedAtMs: 1);
      final otherRoom = playRecord('same', roomId: 'other', playedAtMs: 2);
      final otherSource = playRecord(
        'same',
        source: TrackSource.qq,
        playedAtMs: 3,
      );
      final replay = playRecord('same', playedAtMs: 4);

      final result = [
        first,
        otherRoom,
        otherSource,
      ].fold<List<PlayRecord>>([], recordPlay);
      final deduplicated = recordPlay(result, replay);

      expect(deduplicated.first.playedAtMs, 4);
      expect(deduplicated, hasLength(3));
      expect(
        deduplicated.where((record) => record.roomId == 'other'),
        hasLength(1),
      );
      expect(
        deduplicated.where((record) => record.track.source == TrackSource.qq),
        hasLength(1),
      );
    },
  );

  test('play history does not take a record that would not read back', () {
    final kept = [playRecord('same', playedAtMs: 1)];
    final unreadable = PlayRecord(
      roomId: 'room',
      roomName: '一起听',
      serverOrigin: legacyOrigin,
      track: kept.single.track,
      meta: const TrackMeta(
        title: '歌曲',
        artist: '',
        album: '',
        coverUrl: '',
        pageUrl: '',
        durationMs: -1,
      ),
      playedAtMs: 2,
    );

    expect(recordPlay(kept, unreadable), kept);
  });

  test('play history keeps at most five hundred records', () {
    final records = List.generate(
      501,
      (index) => playRecord('track-$index', playedAtMs: index),
    );
    final result = records.fold<List<PlayRecord>>([], recordPlay);

    expect(result, hasLength(500));
    expect(result.first.track.id, 'track-500');
    expect(result.last.track.id, 'track-1');
  });

  test(
    'play history parser drops malformed values and keeps valid room data',
    () {
      final valid = playRecord('valid', roomId: 'room', playedAtMs: 123);
      final stored = jsonEncode([
        valid.toJson(),
        {
          'track': {'source': 'invalid', 'id': 'bad'},
        },
        'not-an-object',
      ]);

      final result = parsePlays(stored, legacyServerOrigin: legacyOrigin);

      expect(result.single.roomId, 'room');
      expect(result.single.track.id, 'valid');
      expect(parsePlays('{broken', legacyServerOrigin: legacyOrigin), isEmpty);
    },
  );

  test('play history keeps the room name, which records made before it '
      'was kept read back without', () {
    final named = playRecord('named', roomName: '深夜电台', playedAtMs: 1);
    final unnamed = Map<String, Object?>.of(
      playRecord('unnamed', playedAtMs: 2).toJson(),
    )..remove('roomName');

    final result = parsePlays(
      jsonEncode([named.toJson(), unnamed]),
      legacyServerOrigin: legacyOrigin,
    );

    expect(result.map((record) => record.roomName), ['深夜电台', '']);
  });

  test(
    'play history rejects invalid time ranges and required empty fields',
    () {
      final valid = playRecord('valid', roomId: 'room', playedAtMs: 123);
      final negativeDuration = Map<String, Object?>.of(
        valid.toJson()['meta']! as Map<String, Object?>,
      )..['durationMs'] = -1;

      final result = parsePlays(
        jsonEncode([
          valid.toJson(),
          {...valid.toJson(), 'playedAtMs': -1},
          {...valid.toJson(), 'playedAtMs': 8640000000000001},
          {...valid.toJson(), 'meta': negativeDuration},
          {...valid.toJson(), 'roomId': ''},
          {
            ...valid.toJson(),
            'track': {'source': 'netease', 'id': ''},
          },
        ]),
        legacyServerOrigin: legacyOrigin,
      );

      expect(result.single.playedAtMs, 123);
    },
  );

  test('search history trims and deduplicates case-insensitively with the latest source', () {
    final older = SearchRecord(
      query: ' Jazz ',
      source: TrackSource.qq,
      category: SearchCategory.all,
      searchedAtMs: 1,
    );
    final newer = SearchRecord(
      query: 'jazz',
      source: TrackSource.netease,
      category: SearchCategory.tracks,
      searchedAtMs: 2,
    );

    final result = recordSearch([older], newer, 10);

    expect(result.single.query, 'jazz');
    expect(result.single.source, TrackSource.netease);
    expect(result.single.category, SearchCategory.tracks);
  });

  test(
    'search parser keeps newest duplicate and applies the retention limit',
    () {
      final stored = jsonEncode([
        const SearchRecord(
          query: 'One',
          source: TrackSource.qq,
          category: SearchCategory.all,
          searchedAtMs: 1,
        ).toJson(),
        const SearchRecord(
          query: 'one',
          source: TrackSource.netease,
          category: SearchCategory.playlists,
          searchedAtMs: 3,
        ).toJson(),
        const SearchRecord(
          query: 'two',
          source: TrackSource.qq,
          category: SearchCategory.tracks,
          searchedAtMs: 2,
        ).toJson(),
      ]);

      final result = parseSearches(stored, 1);

      expect(result.single.query, 'one');
      expect(result.single.source, TrackSource.netease);
      expect(result.single.searchedAtMs, 3);
    },
  );
}

const legacyOrigin = 'https://livehouse.dihe.moe';

PlayRecord playRecord(
  String id, {
  String roomId = 'room',
  String roomName = '一起听',
  String serverOrigin = legacyOrigin,
  TrackSource source = TrackSource.netease,
  int playedAtMs = 0,
}) {
  return PlayRecord(
    roomId: roomId,
    roomName: roomName,
    serverOrigin: serverOrigin,
    track: Track(source: source, id: id),
    meta: testTrackMeta,
    playedAtMs: playedAtMs,
  );
}
