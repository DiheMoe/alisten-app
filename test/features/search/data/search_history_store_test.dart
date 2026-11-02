import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/search/data/search_history_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;
  late PreferencesSearchHistoryStore store;

  SearchRecord record(String query, int at) {
    return SearchRecord(
      query: query,
      source: TrackSource.qq,
      category: SearchCategory.all,
      searchedAtMs: at,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    store = PreferencesSearchHistoryStore(preferences);
  });

  test(
    'add keeps the newest first, drops repeats and honours the limit',
    () async {
      for (var i = 0; i < 4; i++) {
        await store.add(record('q$i', i), limit: 3);
      }
      await store.add(record('Q2', 10), limit: 3);

      final records = await store.read();
      expect(records.map((r) => r.query), ['Q2', 'q3', 'q1']);
    },
  );

  test('adds that are not awaited one by one are all kept', () async {
    await Future.wait([
      store.add(record('one', 1), limit: 10),
      store.add(record('two', 2), limit: 10),
    ]);

    expect((await store.read()).map((r) => r.query), ['two', 'one']);
  });

  test('truncate(5) keeps only the five most recent records', () async {
    for (var i = 0; i < 8; i++) {
      await store.add(record('q$i', i), limit: 50);
    }

    await store.truncate(5);

    final records = await store.read();
    expect(records.map((r) => r.query), ['q7', 'q6', 'q5', 'q4', 'q3']);
    expect(
      parseSearches(preferences.getString('alisten.search-history'), 50),
      hasLength(5),
    );
  });

  test('clear removes the key and unreadable data reads as empty', () async {
    await store.add(record('q', 1), limit: 10);
    await store.clear();
    expect(preferences.containsKey('alisten.search-history'), isFalse);

    await preferences.setString('alisten.search-history', '{not json');
    expect(await store.read(), isEmpty);
  });
}
