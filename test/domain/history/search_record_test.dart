import 'dart:convert';

import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
