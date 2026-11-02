import 'dart:convert';

import 'package:alisten/domain/history/play_record.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/history/data/local_history_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../domain/history/records_test.dart'
    show legacyOrigin, playRecord;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'store degrades damaged JSON and unknown enums to empty history',
    () async {
      SharedPreferences.setMockInitialValues({
        'alisten.play-history': '{broken',
      });
      final store = LocalHistoryStore(
        await SharedPreferences.getInstance(),
        legacyServerOrigin: legacyOrigin,
      );

      expect(store.loadPlays(), isEmpty);

      SharedPreferences.setMockInitialValues({
        'alisten.play-history': jsonEncode([
          {
            'roomId': 'room',
            'track': {'source': 'unknown', 'id': 'id'},
            'meta': <String, Object?>{},
            'playedAtMs': 1,
          },
        ]),
      });
      expect(store.loadPlays(), isEmpty);
    },
  );

  test('store round-trips records, including one without a title', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = LocalHistoryStore(
      preferences,
      legacyServerOrigin: legacyOrigin,
    );
    final records = [
      playRecord('track', roomId: 'room', playedAtMs: 123),
      PlayRecord(
        roomId: 'room',
        roomName: '',
        serverOrigin: 'https://example.com:8443',
        track: const Track(source: TrackSource.qq, id: 'untitled'),
        meta: const TrackMeta(
          title: '',
          artist: '',
          album: '',
          coverUrl: '',
          pageUrl: '',
          durationMs: 0,
        ),
        playedAtMs: 124,
      ),
    ];

    await store.savePlays(records);

    final loaded = store.loadPlays();
    expect(loaded.map((record) => record.track.id), ['track', 'untitled']);
    expect(loaded.first.roomId, 'room');
    expect(loaded.first.roomName, '一起听');
    expect(loaded.first.playedAtMs, 123);
    expect(loaded.last.meta.title, isEmpty);
    expect(loaded.map((record) => record.serverOrigin), [
      legacyOrigin,
      'https://example.com:8443',
    ]);
  });

  test('a history saved before servers were kept belongs to the legacy '
      'server', () async {
    final old = Map<String, Object?>.of(
      playRecord('old', playedAtMs: 5).toJson(),
    )..remove('serverOrigin');
    SharedPreferences.setMockInitialValues({
      'alisten.play-history': jsonEncode([old]),
    });
    final store = LocalHistoryStore(
      await SharedPreferences.getInstance(),
      legacyServerOrigin: 'https://livehouse.dihe.moe',
    );

    expect(store.loadPlays().single.serverOrigin, 'https://livehouse.dihe.moe');
    expect(store.loadPlays().single.track.id, 'old');
  });

  test('saving writes the server of every record', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = LocalHistoryStore(
      preferences,
      legacyServerOrigin: legacyOrigin,
    );

    await store.savePlays([
      playRecord('legacy'),
      playRecord('other', serverOrigin: 'https://example.com:8443'),
    ]);

    final stored =
        jsonDecode(preferences.getString('alisten.play-history')!)!
            as List<Object?>;
    expect(
      stored.map((record) => (record! as Map<String, Object?>)['serverOrigin']),
      [legacyOrigin, 'https://example.com:8443'],
    );
  });
}
