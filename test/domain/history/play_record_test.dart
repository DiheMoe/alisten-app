import 'dart:convert';

import 'package:alisten/domain/history/play_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'records_test.dart' show legacyOrigin, playRecord;

const _otherOrigin = 'https://example.com:8443';

Map<String, Object?> _withoutServerOrigin(PlayRecord record) {
  return Map<String, Object?>.of(record.toJson())..remove('serverOrigin');
}

void main() {
  test('a record is stored with the server it was played on', () {
    final record = playRecord('track', serverOrigin: _otherOrigin);

    expect(record.toJson()['serverOrigin'], _otherOrigin);
    expect(
      tryPlayRecord(
        record.toJson(),
        legacyServerOrigin: legacyOrigin,
      )!.serverOrigin,
      _otherOrigin,
    );
  });

  test('a record stored before servers were kept belongs to the legacy '
      'server', () {
    final record = tryPlayRecord(
      _withoutServerOrigin(playRecord('old', serverOrigin: _otherOrigin)),
      legacyServerOrigin: legacyOrigin,
    );

    expect(record!.serverOrigin, legacyOrigin);
    expect(record.track.id, 'old');
  });

  test('an empty server origin is the legacy server too', () {
    final stored = {...playRecord('old').toJson(), 'serverOrigin': ''};

    expect(
      tryPlayRecord(stored, legacyServerOrigin: legacyOrigin)!.serverOrigin,
      legacyOrigin,
    );
  });

  test('a server origin that is not text drops the whole record', () {
    final stored = {...playRecord('bad').toJson(), 'serverOrigin': 3};

    expect(tryPlayRecord(stored, legacyServerOrigin: legacyOrigin), isNull);
    expect(
      parsePlays(
        jsonEncode([stored, playRecord('good').toJson()]),
        legacyServerOrigin: legacyOrigin,
      ).map((record) => record.track.id),
      ['good'],
    );
  });

  test('a record with no server to put it on is dropped', () {
    final stored = playRecord('orphan').toJson();

    expect(tryPlayRecord(stored, legacyServerOrigin: ''), isNotNull);
    expect(
      tryPlayRecord({...stored, 'serverOrigin': ''}, legacyServerOrigin: ''),
      isNull,
    );
    expect(recordPlay([], playRecord('orphan', serverOrigin: '')), isEmpty);
  });

  test('parsing gives every old record the legacy server and keeps the '
      'servers of the new ones', () {
    final stored = jsonEncode([
      _withoutServerOrigin(playRecord('old', playedAtMs: 1)),
      playRecord('new', serverOrigin: _otherOrigin, playedAtMs: 2).toJson(),
    ]);

    final plays = parsePlays(
      stored,
      legacyServerOrigin: 'http://127.0.0.1:9876',
    );

    expect(plays.map((record) => record.serverOrigin), [
      'http://127.0.0.1:9876',
      _otherOrigin,
    ]);
  });

  test('the same song in the same room id on two servers is two records', () {
    final first = playRecord('same', roomId: 'room', playedAtMs: 1);
    final second = playRecord(
      'same',
      roomId: 'room',
      serverOrigin: _otherOrigin,
      playedAtMs: 2,
    );

    final plays = recordPlay(recordPlay([], first), second);

    expect(plays.map((record) => record.serverOrigin), [
      _otherOrigin,
      legacyOrigin,
    ]);
    final replay = recordPlay(
      plays,
      playRecord('same', roomId: 'room', playedAtMs: 3),
    );
    expect(replay.map((record) => record.serverOrigin), [
      legacyOrigin,
      _otherOrigin,
    ]);
  });
}
