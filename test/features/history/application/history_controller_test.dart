import 'dart:convert';

import 'package:alisten/core/storage/preferences.dart';
import 'package:alisten/domain/history/play_record.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/history/application/history_controller.dart';
import 'package:alisten/features/history/data/local_history_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/history/records_test.dart'
    show legacyOrigin, playRecord;
import '../../lobby/lobby_test_doubles.dart';
import '../history_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHistoryExporter exporter;

  setUp(() {
    exporter = FakeHistoryExporter();
  });

  Future<ProviderContainer> containerWith(List<PlayRecord> records) async {
    final container = ProviderContainer(
      overrides: [
        await preferencesOverride({
          'alisten.play-history': jsonEncode(
            records.map((record) => record.toJson()).toList(),
          ),
        }),
        playHistoryStoreProvider.overrideWith(
          (ref) => LocalHistoryStore(
            ref.watch(sharedPreferencesProvider),
            legacyServerOrigin: legacyOrigin,
          ),
        ),
        historyExporterProvider.overrideWithValue(exporter),
        historyNowProvider.overrideWithValue(() => 1782864000000),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('stored records are there from the first read', () async {
    final container = await containerWith([playRecord('stored')]);

    expect(
      container.read(historyControllerProvider).records.single.track.id,
      'stored',
    );
  });

  test('the filter matches title, artist and album, ignoring case', () async {
    final target = PlayRecord(
      roomId: 'room',
      roomName: '一起听',
      serverOrigin: legacyOrigin,
      track: const Track(source: TrackSource.netease, id: 'target'),
      meta: const TrackMeta(
        title: 'Target Song',
        artist: 'artist',
        album: 'album',
        coverUrl: '',
        pageUrl: '',
        durationMs: 1000,
      ),
      playedAtMs: 2,
    );
    final container = await containerWith([
      playRecord('other', playedAtMs: 1),
      target,
    ]);
    final controller = container.read(historyControllerProvider.notifier);

    controller.filter('TARGET SONG');
    expect(controller.state.query, 'TARGET SONG');
    expect(controller.state.filteredRecords.single.track.id, 'target');

    controller.filter('');
    expect(controller.state.filteredRecords, hasLength(2));
  });

  test('delete clear and export operate on the intended records', () async {
    final first = playRecord('first', playedAtMs: 1);
    final second = playRecord('second', playedAtMs: 2);
    final container = await containerWith([first, second]);
    final controller = container.read(historyControllerProvider.notifier);
    controller.filter('first');

    await controller.exportHistory();
    expect(exporter.records, hasLength(2));

    await controller.delete(first);
    expect(controller.state.records.single.track.id, 'second');
    await controller.clear();
    expect(controller.state.records, isEmpty);
  });

  test('a deleted record is put back where it played, unless the same song '
      'was recorded in its room meanwhile', () async {
    final newest = playRecord('newest', playedAtMs: 30);
    final middle = playRecord('middle', playedAtMs: 20);
    final oldest = playRecord('oldest', playedAtMs: 10);
    final container = await containerWith([newest, middle, oldest]);
    final controller = container.read(historyControllerProvider.notifier);
    List<String> ids() => [
      for (final record in controller.state.records) record.track.id,
    ];

    await controller.delete(middle);
    await controller.record(playRecord('later', playedAtMs: 40));
    await controller.restore(middle);
    expect(ids(), ['later', 'newest', 'middle', 'oldest']);
    expect(
      container
          .read(playHistoryStoreProvider)
          .loadPlays()
          .map((record) => record.track.id),
      ['later', 'newest', 'middle', 'oldest'],
    );

    await controller.delete(oldest);
    await controller.record(playRecord('oldest', playedAtMs: 50));
    await controller.restore(oldest);
    expect(ids(), ['oldest', 'later', 'newest', 'middle']);
  });

  test('the same song in the same room id on another server is another '
      'record to delete and to put back', () async {
    final here = playRecord('same', playedAtMs: 10);
    final there = playRecord(
      'same',
      serverOrigin: 'https://example.com:8443',
      playedAtMs: 10,
    );
    final container = await containerWith([here, there]);
    final controller = container.read(historyControllerProvider.notifier);

    await controller.delete(here);
    expect(controller.state.records.map((record) => record.serverOrigin), [
      'https://example.com:8443',
    ]);

    await controller.restore(here);
    expect(controller.state.records.map((record) => record.serverOrigin), [
      'https://example.com:8443',
      legacyOrigin,
    ]);
  });

  test('only a record deleted since the last clear can be put back', () async {
    final kept = playRecord('kept', playedAtMs: 20);
    final deleted = playRecord('deleted', playedAtMs: 10);
    final container = await containerWith([kept, deleted]);
    final controller = container.read(historyControllerProvider.notifier);

    await controller.restore(playRecord('never-deleted', playedAtMs: 15));
    expect(controller.state.records, hasLength(2));

    await controller.delete(deleted);
    await controller.clear();
    await controller.restore(deleted);
    expect(controller.state.records, isEmpty);
    expect(container.read(playHistoryStoreProvider).loadPlays(), isEmpty);
  });

  test('the export is stamped with the current time in UTC', () async {
    final container = await containerWith([playRecord('track')]);

    await container.read(historyControllerProvider.notifier).exportHistory();

    expect(exporter.exportedAt!.isUtc, isTrue);
    expect(exporter.exportedAt!.millisecondsSinceEpoch, 1782864000000);
  });
}
