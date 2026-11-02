import 'dart:async';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/realtime/room_commands.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/track/search_page.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/search_history_store.dart';
import 'package:alisten/features/search/application/search_state.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

bool canOpenPlaylists(TrackSource source) => source == TrackSource.netease;

const _cacheLimit = 10;
const _cacheTtlMs = 600000;
const _invalidArgument = 'INVALID_ARGUMENT';
const _keywordTooLong = '关键词太长了，最多 500 个字符。';
const _notConnected = '还没有连上房间，请连接后重试。';
const _unexpected = '出错了，请稍后再试。';
const _logSource = 'search';

final class SearchController extends Notifier<SearchState> {
  SearchController({int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _now;
  // 最久没显示的结果排在最前；只对填入时所在的房间有效。
  final Map<String, ({SearchResults results, int at})> _cache = {};
  String? _roomId;
  int _requestId = 0;
  // 屏幕上的查询正在等待房间连接打开。
  bool _deferred = false;

  @override
  SearchState build() {
    _roomId = ref.read(roomControllerProvider).activeRoomId;
    ref.listen<RoomState>(roomControllerProvider, _onRoom);
    ref.listen(
      settingsControllerProvider.select((s) => s.value.searchHistoryLimit),
      (previous, limit) {
        state = state.copyWith(
          recentSearches: state.recentSearches
              .take(limit)
              .toList(growable: false),
        );
      },
    );
    unawaited(Future.microtask(_loadHistory));
    return const SearchState();
  }

  /// 未给出 [source] 或 [view] 时沿用当前值。搜索会记入最近搜索。
  Future<void> submit(String keyword, {TrackSource? source, SearchView? view}) {
    final selected = source ?? state.source;
    final chosen =
        view ??
        (state.view == SearchView.recommend ? SearchView.all : state.view);
    final shown = chosen == SearchView.playlists && !canOpenPlaylists(selected)
        ? SearchView.all
        : chosen;
    final query = SearchQuery(
      source: selected,
      view: shown,
      keyword: shown == SearchView.recommend ? '' : keyword.trim(),
      page: 1,
    );
    _record(query);
    return _show(query);
  }

  Future<void> changeSource(TrackSource source) {
    if (source != TrackSource.qq && source != TrackSource.netease) {
      return Future.value();
    }
    return submit(state.keyword, source: source);
  }

  Future<void> changeView(SearchView view) {
    return submit(state.keyword, view: view);
  }

  Future<void> loadMore() async {
    final current = state;
    if (!current.hasMore || current.status is SearchLoading) return;
    final query = current.query.withPage(current.page + 1);
    final request = ++_requestId;
    _deferred = false;
    final cached = _cached(query.cacheKey);
    if (cached != null) {
      state = state.copyWith(
        query: query,
        status: const SearchLoaded(),
        results: current.results.append(cached),
      );
      return;
    }
    state = state.copyWith(status: const SearchLoading());
    final roomId = ref.read(roomControllerProvider).activeRoomId;
    final outcome = await _search(query);
    if (_stale(request, roomId)) return;
    final failure = outcome.failure;
    if (failure == null) {
      _remember(query.cacheKey, outcome.results);
      state = state.copyWith(
        query: query,
        status: const SearchLoaded(),
        results: state.results.append(outcome.results),
      );
    } else {
      // 已显示的各页保留，重试时请求同一页。
      state = state.copyWith(
        status: SearchPartial(code: failure.code, message: failure.message),
      );
    }
  }

  Future<void> refreshRecommendations() {
    return _show(
      SearchQuery(
        source: state.source,
        view: SearchView.recommend,
        keyword: '',
        page: 1,
      ),
      force: true,
    );
  }

  /// 不记入最近搜索。
  Future<void> retry() {
    final current = state;
    if (current.status is SearchPartial && current.hasMore) return loadMore();
    return _show(current.query.withPage(1), force: true);
  }

  Future<void> clearHistory() async {
    state = state.copyWith(recentSearches: const []);
    await _writeHistory((store) => store.clear());
  }

  Future<void> _show(SearchQuery query, {bool force = false}) async {
    final request = ++_requestId;
    _deferred = false;
    final unchanged = query == state.query;
    if (query.view != SearchView.recommend && query.keyword.isEmpty) {
      state = state.copyWith(
        query: query,
        status: const SearchIdle(),
        results: SearchResults.empty,
      );
      return;
    }
    final cached = force ? null : _cached(query.cacheKey);
    if (cached != null) {
      state = state.copyWith(
        query: query,
        status: const SearchLoaded(),
        results: cached,
      );
      return;
    }
    final connection = ref.read(roomControllerProvider).status;
    if (connection == RoomConnectionStatus.stopped) {
      state = state.copyWith(
        query: query,
        status: const SearchFailed(code: null, message: _notConnected),
        results: unchanged ? state.results : SearchResults.empty,
      );
      return;
    }
    state = state.copyWith(
      query: query,
      status: const SearchLoading(),
      results: unchanged ? state.results : SearchResults.empty,
    );
    if (connection != RoomConnectionStatus.open) {
      _deferred = true;
      return;
    }
    await _load(query, request);
  }

  Future<void> _load(SearchQuery query, int request) async {
    final roomId = ref.read(roomControllerProvider).activeRoomId;
    final outcome = await _search(query);
    if (_stale(request, roomId)) return;
    final failure = outcome.failure;
    state = state.copyWith(
      status: failure == null
          ? const SearchLoaded()
          : outcome.partial
          ? SearchPartial(code: failure.code, message: failure.message)
          : failure,
      results: outcome.results,
    );
    if (failure == null) _remember(query.cacheKey, outcome.results);
  }

  // 发出请求后若有了更新的请求或换了房间，它的回复既不显示也不写入缓存。
  bool _stale(int request, String? roomId) {
    return !ref.mounted ||
        request != _requestId ||
        roomId != ref.read(roomControllerProvider).activeRoomId;
  }

  Future<_Outcome> _search(SearchQuery query) async {
    if (query.view == SearchView.recommend) {
      final part = await _capture(query, (c) => c.recommendations());
      final items = part.value;
      return items == null
          ? _Outcome(SearchResults.empty, part.failure, partial: false)
          : _Outcome(SearchResults(recommendations: items), null);
    }
    final withTracks =
        query.view == SearchView.all || query.view == SearchView.tracks;
    final withPlaylists =
        query.view == SearchView.playlists ||
        (query.view == SearchView.all && canOpenPlaylists(query.source));
    final Future<_Part<SearchPage<TrackSummary>>?> tracksRequest = withTracks
        ? _capture(
            query,
            (c) => c.searchTracks(
              source: query.source,
              keyword: query.keyword,
              page: query.page,
              pageSize: searchPageSize,
            ),
          )
        : Future.value();
    final Future<_Part<SearchPage<PlaylistSummary>>?> playlistsRequest =
        withPlaylists
        ? _capture(
            query,
            (c) => c.searchPlaylists(
              source: query.source,
              keyword: query.keyword,
              page: query.page,
              pageSize: searchPageSize,
            ),
          )
        : Future.value();
    final (tracks, playlists) = await (tracksRequest, playlistsRequest).wait;
    final failures = [?tracks?.failure, ?playlists?.failure];
    final asked = [?tracks, ?playlists].length;
    return _Outcome(
      SearchResults(
        tracks: tracks?.value?.items ?? const [],
        tracksTotal: tracks?.value?.total ?? 0,
        playlists: playlists?.value?.items ?? const [],
        playlistsTotal: playlists?.value?.total ?? 0,
      ),
      failures.isEmpty ? null : failures.first,
      partial: failures.length < asked,
    );
  }

  // 不抛出：任何失败都作为结果返回，界面才不会一直停在加载中。
  Future<_Part<T>> _capture<T>(
    SearchQuery query,
    Future<T> Function(RoomCommands c) run,
  ) async {
    try {
      final value = await ref.read(roomControllerProvider.notifier).query(run);
      return _Part.value(value);
    } on RoomRequestException catch (error) {
      final text =
          error.code == _invalidArgument && query.view != SearchView.recommend
          ? _keywordTooLong
          : error.message;
      return _Part.failure(SearchFailed(code: error.code, message: text));
    } on Object {
      AppLog.warn(_logSource, 'search failed unexpectedly');
      return const _Part.failure(
        SearchFailed(code: null, message: _unexpected),
      );
    }
  }

  SearchResults? _cached(String key) {
    final entry = _cache.remove(key);
    if (entry == null || _now() - entry.at >= _cacheTtlMs) return null;
    _cache[key] = entry;
    return entry.results;
  }

  void _remember(String key, SearchResults results) {
    final at = _now();
    _cache.removeWhere((_, entry) => at - entry.at >= _cacheTtlMs);
    _cache.remove(key);
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[key] = (results: results, at: at);
  }

  void _record(SearchQuery query) {
    final settings = ref.read(settingsControllerProvider).value;
    if (!settings.recordSearch ||
        query.keyword.isEmpty ||
        query.view == SearchView.recommend) {
      return;
    }
    final record = SearchRecord(
      query: query.keyword,
      source: query.source,
      category: switch (query.view) {
        SearchView.tracks => SearchCategory.tracks,
        SearchView.playlists => SearchCategory.playlists,
        SearchView.all || SearchView.recommend => SearchCategory.all,
      },
      searchedAtMs: _now(),
    );
    final limit = settings.searchHistoryLimit;
    state = state.copyWith(
      recentSearches: recordSearch(state.recentSearches, record, limit),
    );
    unawaited(_writeHistory((store) => store.add(record, limit: limit)));
  }

  Future<void> _loadHistory() async {
    try {
      final stored = await ref.read(searchHistoryStoreProvider).read();
      if (!ref.mounted) return;
      final limit = ref
          .read(settingsControllerProvider)
          .value
          .searchHistoryLimit;
      // 读取期间新做的搜索比读到的记录更新。
      final made = state.recentSearches;
      final known = {for (final record in made) _queryKey(record.query)};
      state = state.copyWith(
        recentSearches: [
          ...made,
          ...stored.where((record) => !known.contains(_queryKey(record.query))),
        ].take(limit).toList(growable: false),
      );
    } on Object {
      AppLog.warn(_logSource, 'history not read');
    }
  }

  // 最近搜索写入失败不能影响搜索本身。
  Future<void> _writeHistory(
    Future<void> Function(SearchHistoryStore store) write,
  ) async {
    try {
      await write(ref.read(searchHistoryStoreProvider));
    } on Object {
      AppLog.warn(_logSource, 'history not saved');
    }
  }

  void _onRoom(RoomState? previous, RoomState next) {
    if (_roomId != next.activeRoomId) {
      _roomId = next.activeRoomId;
      _cache.clear();
      _deferred = false;
      _requestId++;
      state = SearchState(recentSearches: state.recentSearches);
      return;
    }
    if (!_deferred) return;
    switch (next.status) {
      case RoomConnectionStatus.open:
        _deferred = false;
        unawaited(_load(state.query, ++_requestId));
      case RoomConnectionStatus.stopped:
        _deferred = false;
        _requestId++;
        state = state.copyWith(
          status: const SearchFailed(code: null, message: _notConnected),
        );
      case RoomConnectionStatus.connecting || RoomConnectionStatus.reconnecting:
        return;
    }
  }
}

String _queryKey(String query) => query.trim().toLowerCase();

final class _Part<T> {
  const _Part.value(T this.value) : failure = null;
  const _Part.failure(SearchFailed this.failure) : value = null;

  final T? value;
  final SearchFailed? failure;
}

// [failure] 是第一个失败；[partial] 表示其他部分有结果，照常显示。
final class _Outcome {
  const _Outcome(this.results, this.failure, {this.partial = false});

  final SearchResults results;
  final SearchFailed? failure;
  final bool partial;
}
