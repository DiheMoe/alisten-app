import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/realtime/room_commands.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/search_history_store.dart';
import 'package:alisten/features/search/application/search_state.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

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
  // 歌曲页、歌单页和推荐分开存，总览由歌曲和歌单的第一页拼成。最久没显示的
  // 排在最前；只对填入时所在的房间有效。
  final Map<String, ({SearchResults results, int at})> _cache = {};
  // 翻到过空页的搜索，记下它真正的最后一页。
  final Map<String, int> _lastPages = {};
  String? _roomId;
  int _requestId = 0;
  // 屏幕上的查询正在等待房间连接打开；[fresh] 表示它不能用缓存。
  ({bool fresh})? _deferred;

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
    final shown =
        view ??
        (state.view == SearchView.recommend ? SearchView.all : state.view);
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

  /// 换到第 [page] 页。取这一页期间仍显示当前页。
  Future<PageTurnOutcome> turnTo(int page) async {
    final current = state;
    if (page < 1 ||
        page > current.pageCount ||
        page == current.page ||
        current.status is SearchLoading) {
      return PageTurnOutcome.ignored;
    }
    final query = current.query.withPage(page);
    final request = ++_requestId;
    _deferred = null;
    var results = _cachedResults(query);
    if (results == null) {
      state = state.copyWith(status: SearchLoading(page: page));
      final roomId = ref.read(roomControllerProvider).activeRoomId;
      final outcome = await _search(query);
      if (_stale(request, roomId)) return PageTurnOutcome.ignored;
      _rememberFetched(query, outcome);
      final failure = outcome.failure;
      if (failure != null) {
        state = state.copyWith(
          status: SearchPartial(
            code: failure.code,
            message: failure.message,
            page: page,
          ),
        );
        return PageTurnOutcome.failed;
      }
      results = outcome.results;
    }
    final kind = _kindsOf(query).single;
    if (_isEmpty(results, kind)) {
      _lastPages[_searchKey(query, kind)] = page - 1;
      state = state.copyWith(
        status: const SearchLoaded(),
        results: _capped(current.query, current.results),
      );
      return PageTurnOutcome.pastEnd;
    }
    state = state.copyWith(
      query: query,
      status: const SearchLoaded(),
      results: _capped(query, results),
    );
    return PageTurnOutcome.turned;
  }

  Future<void> refreshRecommendations() {
    return _show(
      SearchQuery(
        source: state.source,
        view: SearchView.recommend,
        keyword: '',
        page: 1,
      ),
      fresh: true,
    );
  }

  /// 不记入最近搜索。
  Future<void> retry() => _show(state.query);

  Future<void> clearHistory() async {
    state = state.copyWith(recentSearches: const []);
    await _writeHistory((store) => store.clear());
  }

  Future<void> _show(SearchQuery query, {bool fresh = false}) async {
    final request = ++_requestId;
    _deferred = null;
    final unchanged = query == state.query;
    if (query.view != SearchView.recommend && query.keyword.isEmpty) {
      state = state.copyWith(
        query: query,
        status: const SearchIdle(),
        results: SearchResults.empty,
      );
      return;
    }
    final cached = fresh ? null : _cachedResults(query);
    if (cached != null) {
      state = state.copyWith(
        query: query,
        status: const SearchLoaded(),
        results: _capped(query, cached),
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
      _deferred = (fresh: fresh);
      return;
    }
    await _load(query, request, fresh: fresh);
  }

  Future<void> _load(
    SearchQuery query,
    int request, {
    required bool fresh,
  }) async {
    final roomId = ref.read(roomControllerProvider).activeRoomId;
    final outcome = await _search(query, fresh: fresh);
    if (_stale(request, roomId)) return;
    _rememberFetched(query, outcome);
    final failure = outcome.failure;
    state = state.copyWith(
      status: failure == null
          ? const SearchLoaded()
          : outcome.partial
          ? SearchPartial(code: failure.code, message: failure.message)
          : failure,
      results: _capped(query, outcome.results),
    );
  }

  // 发出请求后若有了更新的请求或换了房间，它的回复既不显示也不写入缓存。
  bool _stale(int request, String? roomId) {
    return !ref.mounted ||
        request != _requestId ||
        roomId != ref.read(roomControllerProvider).activeRoomId;
  }

  Future<_Outcome> _search(SearchQuery query, {bool fresh = false}) async {
    final kinds = _kindsOf(query);
    final parts = await Future.wait([
      for (final kind in kinds) _part(query, kind, fresh: fresh),
    ]);
    final failures = [for (final part in parts) ?part.failure];
    return _Outcome(
      {for (final (index, kind) in kinds.indexed) kind: ?parts[index].value},
      fetched: {
        for (final (index, kind) in kinds.indexed)
          if (parts[index].fetched) kind,
      },
      failure: failures.firstOrNull,
      partial: failures.length < kinds.length,
    );
  }

  Future<_Part> _part(
    SearchQuery query,
    _Kind kind, {
    required bool fresh,
  }) async {
    final cached = fresh ? null : _cached(_key(query, kind));
    if (cached != null) return _Part.cached(cached);
    return switch (kind) {
      _Kind.tracks => _capture(query, (c) async {
        final page = await c.searchTracks(
          source: query.source,
          keyword: query.keyword,
          page: query.page,
          pageSize: searchPageSize,
        );
        return SearchResults(tracks: page.items, tracksTotal: page.total);
      }),
      _Kind.playlists => _capture(query, (c) async {
        final page = await c.searchPlaylists(
          source: query.source,
          keyword: query.keyword,
          page: query.page,
          pageSize: searchPageSize,
        );
        return SearchResults(playlists: page.items, playlistsTotal: page.total);
      }),
      _Kind.recommendations => _capture(
        query,
        (c) async => SearchResults(recommendations: await c.recommendations()),
      ),
    };
  }

  // 不抛出：任何失败都作为结果返回，界面才不会一直停在加载中。
  Future<_Part> _capture(
    SearchQuery query,
    Future<SearchResults> Function(RoomCommands c) run,
  ) async {
    try {
      final value = await ref.read(roomControllerProvider.notifier).query(run);
      return _Part.fetched(value);
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

  SearchResults? _cachedResults(SearchQuery query) {
    final parts = {
      for (final kind in _kindsOf(query)) kind: ?_cached(_key(query, kind)),
    };
    return parts.length == _kindsOf(query).length ? _combine(parts) : null;
  }

  // 只记新取回的部分，取自缓存的不因此多留十分钟。重新取回第一页时，以前
  // 记下的最后一页不再作数。
  void _rememberFetched(SearchQuery query, _Outcome outcome) {
    for (final kind in outcome.fetched) {
      _remember(_key(query, kind), outcome.parts[kind]!);
      if (query.page == 1) _lastPages.remove(_searchKey(query, kind));
    }
  }

  // 平台给出的总数可能比它肯给的多：总数不超过已知的最后一页。
  SearchResults _capped(SearchQuery query, SearchResults results) {
    int capped(int total, _Kind kind) {
      final last = _lastPages[_searchKey(query, kind)];
      return last == null ? total : math.min(total, last * searchPageSize);
    }

    return SearchResults(
      tracks: results.tracks,
      tracksTotal: capped(results.tracksTotal, _Kind.tracks),
      playlists: results.playlists,
      playlistsTotal: capped(results.playlistsTotal, _Kind.playlists),
      recommendations: results.recommendations,
    );
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
      _lastPages.clear();
      _deferred = null;
      _requestId++;
      state = SearchState(recentSearches: state.recentSearches);
      return;
    }
    final deferred = _deferred;
    if (deferred == null) return;
    switch (next.status) {
      case RoomConnectionStatus.open:
        _deferred = null;
        unawaited(_load(state.query, ++_requestId, fresh: deferred.fresh));
      case RoomConnectionStatus.stopped:
        _deferred = null;
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

enum _Kind { tracks, playlists, recommendations }

List<_Kind> _kindsOf(SearchQuery query) => switch (query.view) {
  SearchView.all => const [_Kind.tracks, _Kind.playlists],
  SearchView.tracks => const [_Kind.tracks],
  SearchView.playlists => const [_Kind.playlists],
  SearchView.recommend => const [_Kind.recommendations],
};

// 推荐与音源、关键词和页码无关。
String _searchKey(SearchQuery query, _Kind kind) =>
    kind == _Kind.recommendations
    ? kind.name
    : '${query.source.name}|${kind.name}|${query.keyword}';

String _key(SearchQuery query, _Kind kind) =>
    '${query.page}|${_searchKey(query, kind)}';

bool _isEmpty(SearchResults results, _Kind kind) => switch (kind) {
  _Kind.tracks => results.tracks.isEmpty,
  _Kind.playlists => results.playlists.isEmpty,
  _Kind.recommendations => results.recommendations.isEmpty,
};

// 每个部分只填了自己的字段。
SearchResults _combine(Map<_Kind, SearchResults> parts) => SearchResults(
  tracks: parts[_Kind.tracks]?.tracks ?? const [],
  tracksTotal: parts[_Kind.tracks]?.tracksTotal ?? 0,
  playlists: parts[_Kind.playlists]?.playlists ?? const [],
  playlistsTotal: parts[_Kind.playlists]?.playlistsTotal ?? 0,
  recommendations: parts[_Kind.recommendations]?.recommendations ?? const [],
);

final class _Part {
  const _Part.cached(SearchResults this.value)
    : failure = null,
      fetched = false;
  const _Part.fetched(SearchResults this.value)
    : failure = null,
      fetched = true;
  const _Part.failure(SearchFailed this.failure)
    : value = null,
      fetched = false;

  final SearchResults? value;
  final SearchFailed? failure;
  final bool fetched;
}

// [failure] 是第一个失败；[partial] 表示其他部分有结果，照常显示。
final class _Outcome {
  _Outcome(
    this.parts, {
    required this.fetched,
    required this.failure,
    required this.partial,
  }) : results = _combine(parts);

  final Map<_Kind, SearchResults> parts;
  final Set<_Kind> fetched;
  final SearchResults results;
  final SearchFailed? failure;
  final bool partial;
}
