import 'package:alisten/domain/history/search_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final searchHistoryStoreProvider = Provider<SearchHistoryStore>((ref) {
  throw UnimplementedError('searchHistoryStore 未注入');
});

abstract interface class SearchHistoryStore {
  /// 按搜索时间从新到旧排列。
  Future<List<SearchRecord>> read();

  /// 把 [record] 放在最前并替换同一关键词的旧记录，最多保留 [limit] 条。
  Future<void> add(SearchRecord record, {required int limit});

  Future<void> truncate(int limit);

  Future<void> clear();
}
