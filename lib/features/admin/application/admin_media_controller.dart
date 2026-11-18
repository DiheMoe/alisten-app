import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const mediaPageSize = 20;

/// 服务端每页条数，以回复里的为准。
const _serverPageSize = 50;

/// 服务端一次最多删这么多。
const _removalBatch = 50;
const _searchDelay = Duration(milliseconds: 300);
const _notLoadedText = '没能读取存储的歌曲，请稍后重试。';
const _sessionEndedText = '后台已退出，歌曲没有删除。';
const _sessionEndedPartlyText = '后台已退出，余下的歌曲没有删除。';

({int first, int last, int offset}) mediaWindow(
  int page, {
  int size = mediaPageSize,
  int serverSize = _serverPageSize,
}) {
  final start = (page - 1) * size;
  final first = start ~/ serverSize + 1;
  final last = (start + size - 1) ~/ serverSize + 1;
  return (first: first, last: last, offset: start - (first - 1) * serverSize);
}

final class AdminMediaState {
  const AdminMediaState({
    this.query = '',
    this.order = MediaOrder.stored,
    this.page = 1,
    this.items = const [],
    this.total,
    this.totalBytes,
    this.loading = false,
    this.error,
    this.selected = const {},
    this.removing = false,
  });

  final String query;
  final MediaOrder order;
  final int page;
  final List<StoredTrack> items;
  final int? total;
  final int? totalBytes;
  final bool loading;
  final String? error;
  final Map<String, StoredTrack> selected;
  final bool removing;

  int get pageCount =>
      math.max(1, ((total ?? 0) + mediaPageSize - 1) ~/ mediaPageSize);

  int get selectedBytes =>
      selected.values.fold(0, (sum, track) => sum + track.bytes);

  bool get selecting => selected.isNotEmpty;

  bool get pageSelected =>
      items.isNotEmpty && items.every((t) => selected.containsKey(t.key));

  AdminMediaState copyWith({
    String? query,
    MediaOrder? order,
    int? page,
    List<StoredTrack>? items,
    int? total,
    int? totalBytes,
    bool? loading,
    String? Function()? error,
    Map<String, StoredTrack>? selected,
    bool? removing,
  }) => AdminMediaState(
    query: query ?? this.query,
    order: order ?? this.order,
    page: page ?? this.page,
    items: items ?? this.items,
    total: total ?? this.total,
    totalBytes: totalBytes ?? this.totalBytes,
    loading: loading ?? this.loading,
    error: error == null ? this.error : error(),
    selected: selected ?? this.selected,
    removing: removing ?? this.removing,
  );
}

sealed class MediaRemovalOutcome {
  const MediaRemovalOutcome();
}

final class MediaRemoved extends MediaRemovalOutcome {
  const MediaRemoved({required this.deleted, required this.inUse});
  final int deleted;
  final int inUse;
}

final class MediaRemovalFailed extends MediaRemovalOutcome {
  const MediaRemovalFailed({required this.message, required this.deleted});
  final String message;
  final int deleted;
}

final class MediaRemovalUnknown extends MediaRemovalOutcome {
  const MediaRemovalUnknown({required this.deleted});
  final int deleted;
}

final class MediaRemovalNotSent extends MediaRemovalOutcome {
  const MediaRemovalNotSent(this.message);
  final String message;
}

final adminMediaControllerProvider =
    NotifierProvider.autoDispose<AdminMediaController, AdminMediaState>(
      AdminMediaController.new,
    );

final adminMediaSummaryProvider =
    FutureProvider.autoDispose<({int total, int totalBytes})>(
      (ref) async {
        final page = await ref
            .read(adminSessionProvider.notifier)
            .run(
              (api, token) => api.listMedia(
                token,
                page: 1,
                order: MediaOrder.stored,
                query: '',
              ),
            );
        return (total: page.total, totalBytes: page.totalBytes);
      },
      // 读取失败时首页那一行显示“读取失败”，不在后台一遍遍重试。
      retry: (_, _) => null,
    );

final class AdminMediaController extends Notifier<AdminMediaState> {
  // 读到的服务端页，按搜索词和排序；任何一项变了就清空。
  final Map<int, Future<MediaPage>> _pages = {};
  int _serverSize = _serverPageSize;
  int _loads = 0;
  int _failedPage = 1;
  Timer? _search;

  @override
  AdminMediaState build() {
    ref.onDispose(() => _search?.cancel());
    return const AdminMediaState();
  }

  Future<void> load() => _show(state.page);

  /// 下拉刷新：首页那一行的合计也重新读。
  Future<void> refresh() {
    _pages.clear();
    if (ref.exists(adminMediaSummaryProvider)) {
      ref.invalidate(adminMediaSummaryProvider);
    }
    return _show(state.page);
  }

  Future<void> retry() => _show(_failedPage);

  Future<void> goTo(int page) => _show(page.clamp(1, state.pageCount));

  void setQuery(String query) {
    _search?.cancel();
    final text = query.trim();
    _search = ref.read(adminTimerProvider)(_searchDelay, () {
      _search = null;
      if (ref.mounted && text != state.query) unawaited(_restart(query: text));
    });
  }

  Future<void> clearQuery() {
    _search?.cancel();
    _search = null;
    return _restart(query: '');
  }

  Future<void> setOrder(MediaOrder order) =>
      order == state.order ? Future.value() : _restart(order: order);

  void toggle(StoredTrack track) {
    final selected = Map.of(state.selected);
    if (selected.remove(track.key) == null) selected[track.key] = track;
    state = state.copyWith(selected: selected);
  }

  void togglePage() {
    final selected = Map.of(state.selected);
    if (state.pageSelected) {
      for (final track in state.items) {
        selected.remove(track.key);
      }
    } else {
      for (final track in state.items) {
        selected[track.key] = track;
      }
    }
    state = state.copyWith(selected: selected);
  }

  void clearSelection() => state = state.copyWith(selected: const {});

  Future<MediaRemovalOutcome> remove(List<StoredTrack> tracks) async {
    // 离开页面不能打断删除后的汇总刷新和重新读取。
    final link = ref.keepAlive();
    try {
      return await _remove(tracks);
    } finally {
      link.close();
    }
  }

  Future<MediaRemovalOutcome> _remove(List<StoredTrack> tracks) async {
    final session = ref.read(adminSessionProvider.notifier);
    state = state.copyWith(removing: true);
    final deleted = <String>{};
    final inUse = <String>{};
    final settled = <String>{};
    MediaRemovalOutcome? stopped;
    for (var start = 0; start < tracks.length; start += _removalBatch) {
      final keys = [
        for (final track in tracks.skip(start).take(_removalBatch)) track.key,
      ];
      final result = await session.change(
        (api, token) => api.removeMedia(token, keys),
        unexpected: 'media removal ended unexpectedly',
        sessionEnded: deleted.isEmpty
            ? _sessionEndedText
            : _sessionEndedPartlyText,
        reread: (_) async {},
      );
      switch (result) {
        case MutationSucceeded(:final value):
          deleted.addAll(value.deleted);
          inUse.addAll(value.inUse);
          settled.addAll(keys);
        case MutationFailed(:final message):
          stopped = MediaRemovalFailed(
            message: message,
            deleted: deleted.length,
          );
        case MutationUnknown():
          stopped = MediaRemovalUnknown(deleted: deleted.length);
        case MutationNotSent(:final message):
          stopped = deleted.isEmpty
              ? MediaRemovalNotSent(message)
              : MediaRemovalFailed(message: message, deleted: deleted.length);
      }
      if (stopped != null) break;
    }
    if (!ref.mounted) {
      return stopped ??
          MediaRemoved(deleted: deleted.length, inUse: inUse.length);
    }
    state = state.copyWith(
      removing: false,
      selected: {
        for (final entry in state.selected.entries)
          if (!settled.contains(entry.key) || inUse.contains(entry.key))
            entry.key: entry.value,
      },
    );
    ref.invalidate(adminMediaSummaryProvider);
    _pages.clear();
    await _show(state.page);
    return stopped ??
        MediaRemoved(deleted: deleted.length, inUse: inUse.length);
  }

  // 不带搜索时读到的合计就是整个曲库的：首页那一行读取失败或已过时，就让它
  // 重新读；一致时不再多发请求。
  void _mendSummary(int total, int totalBytes) {
    if (!ref.exists(adminMediaSummaryProvider)) return;
    final summary = ref.read(adminMediaSummaryProvider);
    if (summary.isLoading) return;
    if (!summary.hasError &&
        summary.value == (total: total, totalBytes: totalBytes)) {
      return;
    }
    ref.invalidate(adminMediaSummaryProvider);
  }

  // 换了搜索词或排序，旧的条目和合计都不再作数：清掉，读回之前按首次读取
  // 显示，不会先报“没有歌曲”。
  Future<void> _restart({String? query, MediaOrder? order}) {
    _pages.clear();
    state = AdminMediaState(
      query: query ?? state.query,
      order: order ?? state.order,
      removing: state.removing,
    );
    return _show(1);
  }

  Future<MediaPage> _serverPage(int page) {
    final query = state.query;
    final order = state.order;
    return _pages[page] ??= _fetch(page, query, order);
  }

  Future<MediaPage> _fetch(int page, String query, MediaOrder order) async {
    try {
      final answer = await ref
          .read(adminSessionProvider.notifier)
          .run(
            (api, token) =>
                api.listMedia(token, page: page, order: order, query: query),
          );
      if (answer.pageSize != _serverSize) {
        _pages.clear();
        _serverSize = answer.pageSize;
      }
      return answer;
    } on Object {
      _pages.removeWhere((key, _) => key == page);
      rethrow;
    }
  }

  Future<void> _show(int page) async {
    final load = ++_loads;
    final query = state.query;
    final order = state.order;
    state = state.copyWith(loading: true, error: () => null);
    try {
      final (:first, :last, :offset) = mediaWindow(
        page,
        serverSize: _serverSize,
      );
      final answers = await Future.wait([
        for (var p = first; p <= last; p++) _serverPage(p),
      ]);
      if (!ref.mounted || load != _loads) return;
      if (query != state.query || order != state.order) return;
      final seen = <String>{};
      final joined = [
        for (final answer in answers)
          for (final track in answer.items)
            if (seen.add(track.key)) track,
      ];
      final latest = answers.last;
      final items = joined.skip(offset).take(mediaPageSize).toList();
      final lastPage = math.max(
        1,
        (latest.total + mediaPageSize - 1) ~/ mediaPageSize,
      );
      // 删除后这一页可能已超出最后一页：退到最后一页。
      if (items.isEmpty && page > lastPage) return await _show(lastPage);
      state = state.copyWith(
        page: page,
        items: items,
        total: latest.total,
        totalBytes: latest.totalBytes,
        loading: false,
      );
      if (query.isEmpty) _mendSummary(latest.total, latest.totalBytes);
    } on AdminSessionEnded {
      if (ref.mounted && load == _loads) {
        state = state.copyWith(loading: false);
      }
    } on Object catch (error) {
      if (!ref.mounted || load != _loads) return;
      _failedPage = page;
      final message = switch (error) {
        ApiException(:final message) => message,
        _ => _notLoadedText,
      };
      if (error is! ApiException) {
        AppLog.warn('admin', 'media not loaded', type: '${error.runtimeType}');
      }
      state = state.copyWith(loading: false, error: () => message);
    }
  }
}
