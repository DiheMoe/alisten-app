import 'package:alisten/domain/history/stored_list.dart';
import 'package:alisten/domain/track/track.dart';

enum SearchCategory { all, tracks, playlists }

/// 必须从小到大排列，最后一个即最多保存的条数。
const searchHistoryLimits = [5, 10, 20, 50];

final class SearchRecord {
  const SearchRecord({
    required this.query,
    required this.source,
    required this.category,
    required this.searchedAtMs,
  });

  final String query;
  final TrackSource source;
  final SearchCategory category;
  final int searchedAtMs;

  Map<String, Object?> toJson() {
    return {
      'query': query,
      'source': source.name,
      'category': category.name,
      'searchedAtMs': searchedAtMs,
    };
  }
}

List<SearchRecord> recordSearch(
  List<SearchRecord> searches,
  SearchRecord record,
  int limit,
) {
  final query = record.query.trim();
  if (query.isEmpty) return searches.take(limit).toList(growable: false);
  final key = query.toLowerCase();
  final normalized = SearchRecord(
    query: query,
    source: record.source,
    category: record.category,
    searchedAtMs: record.searchedAtMs,
  );
  return [
    normalized,
    ...searches.where((search) => _queryKey(search.query) != key),
  ].take(limit).toList(growable: false);
}

List<SearchRecord> parseSearches(String? stored, int limit) {
  final latest = <String, SearchRecord>{};
  for (final item in readStoredList(stored)) {
    final record = _trySearchRecord(item);
    if (record == null) continue;
    final key = _queryKey(record.query);
    if (key.isEmpty) continue;
    final previous = latest[key];
    if (previous == null || record.searchedAtMs > previous.searchedAtMs) {
      latest[key] = SearchRecord(
        query: record.query.trim(),
        source: record.source,
        category: record.category,
        searchedAtMs: record.searchedAtMs,
      );
    }
  }
  final records = latest.values.toList()
    ..sort((a, b) => b.searchedAtMs.compareTo(a.searchedAtMs));
  return records.take(limit).toList(growable: false);
}

SearchRecord? _trySearchRecord(Object? value) {
  if (value is! Map<String, Object?>) return null;
  final query = value['query'];
  final source = value['source'];
  final category = value['category'];
  final searchedAtMs = value['searchedAtMs'];
  if (query is! String || searchedAtMs is! int) return null;
  if (source != 'netease' && source != 'qq') return null;
  final trackSource = source == 'netease'
      ? TrackSource.netease
      : TrackSource.qq;
  for (final candidate in SearchCategory.values) {
    if (candidate.name == category) {
      return SearchRecord(
        query: query,
        source: trackSource,
        category: candidate,
        searchedAtMs: searchedAtMs,
      );
    }
  }
  return null;
}

String _queryKey(String query) => query.trim().toLowerCase();
