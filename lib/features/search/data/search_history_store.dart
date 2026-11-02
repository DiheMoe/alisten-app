import 'dart:convert';

import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/features/search/application/search_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// `alisten.search-history` 键只由这里读写。
final class PreferencesSearchHistoryStore implements SearchHistoryStore {
  const PreferencesSearchHistoryStore(this._preferences);

  static const _key = 'alisten.search-history';

  static final _stored = searchHistoryLimits.last;

  final SharedPreferences _preferences;

  @override
  Future<List<SearchRecord>> read() async => _records();

  // 读取记录和发起写入之间不能有 await，否则接连的几次添加会丢掉彼此的记录。
  @override
  Future<void> add(SearchRecord record, {required int limit}) {
    return _write(recordSearch(_records(), record, limit));
  }

  @override
  Future<void> truncate(int limit) {
    final stored = _preferences.getString(_key);
    if (stored == null) return Future.value();
    return _write(parseSearches(stored, limit));
  }

  @override
  Future<void> clear() async {
    if (!await _preferences.remove(_key)) {
      throw StateError('Search history could not be cleared');
    }
  }

  List<SearchRecord> _records() {
    return parseSearches(_preferences.getString(_key), _stored);
  }

  Future<void> _write(List<SearchRecord> records) async {
    final saved = await _preferences.setString(
      _key,
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
    if (!saved) throw StateError('Search history could not be saved');
  }
}
