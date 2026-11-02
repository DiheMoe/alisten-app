import 'package:alisten/domain/history/play_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class PlayHistoryStore {
  List<PlayRecord> loadPlays();

  Future<void> savePlays(List<PlayRecord> records);
}

abstract interface class HistoryExporter {
  Future<void> export(List<PlayRecord> records, DateTime exportedAtUtc);
}

final playHistoryStoreProvider = Provider<PlayHistoryStore>((ref) {
  throw UnimplementedError('playHistoryStore 未注入');
});

final historyExporterProvider = Provider<HistoryExporter>((ref) {
  throw UnimplementedError('historyExporter 未注入');
});

final historyNowProvider = Provider<int Function()>((ref) {
  return () => DateTime.now().millisecondsSinceEpoch;
});

final historyControllerProvider =
    NotifierProvider<HistoryController, HistoryState>(HistoryController.new);

final class HistoryState {
  const HistoryState({this.records = const [], this.query = ''});

  /// 最近播放的在前。
  final List<PlayRecord> records;

  /// 原样保存筛选词，页面重建时筛选框据此回显。
  final String query;

  List<PlayRecord> get filteredRecords {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return records;
    return records
        .where(
          (record) =>
              record.meta.title.toLowerCase().contains(keyword) ||
              record.meta.artist.toLowerCase().contains(keyword) ||
              record.meta.album.toLowerCase().contains(keyword),
        )
        .toList(growable: false);
  }

  HistoryState copyWith({List<PlayRecord>? records, String? query}) {
    return HistoryState(
      records: records ?? this.records,
      query: query ?? this.query,
    );
  }
}

final class HistoryController extends Notifier<HistoryState> {
  final _restorable = Set<PlayRecord>.identity();

  @override
  HistoryState build() {
    // 偏好设置此时已经加载完毕，历史可以同步读出。
    return HistoryState(
      records: ref.read(playHistoryStoreProvider).loadPlays(),
    );
  }

  Future<void> record(PlayRecord record) {
    state = state.copyWith(records: recordPlay(state.records, record));
    return _save();
  }

  void filter(String query) {
    state = state.copyWith(query: query);
  }

  Future<void> delete(PlayRecord record) {
    _restorable.add(record);
    state = state.copyWith(
      records: state.records
          .where(
            (item) =>
                !item.isSameSongAs(record) ||
                item.playedAtMs != record.playedAtMs,
          )
          .toList(growable: false),
    );
    return _save();
  }

  /// 把 [delete] 删掉的记录按播放时间放回原处，每条只能放回一次。此后清空过
  /// 历史，或同一服务器同一房间的同一首歌又被记录过时不再放回，因为每个房间的
  /// 每首歌只保留最近一次播放。
  Future<void> restore(PlayRecord record) async {
    if (!_restorable.remove(record)) return;
    final records = state.records;
    if (records.any((item) => item.isSameSongAs(record))) return;
    var at = records.indexWhere((item) => item.playedAtMs < record.playedAtMs);
    if (at < 0) at = records.length;
    state = state.copyWith(
      records: [
        ...records.take(at),
        record,
        ...records.skip(at),
      ].take(playHistoryLimit).toList(growable: false),
    );
    await _save();
  }

  Future<void> clear() {
    _restorable.clear();
    state = state.copyWith(records: const []);
    return _save();
  }

  Future<void> exportHistory() {
    final now = DateTime.fromMillisecondsSinceEpoch(
      ref.read(historyNowProvider)(),
      isUtc: true,
    );
    return ref.read(historyExporterProvider).export(state.records, now);
  }

  Future<void> _save() {
    return ref.read(playHistoryStoreProvider).savePlays(state.records);
  }
}
