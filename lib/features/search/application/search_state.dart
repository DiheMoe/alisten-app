import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/track/track.dart';

enum SearchView { all, tracks, playlists, recommend }

const searchPageSize = 20;

/// 每个请求都带着发出时的查询，回复对应自己的查询，而不是屏幕上当前的查询。
final class SearchQuery {
  const SearchQuery({
    required this.source,
    required this.view,
    required this.keyword,
    required this.page,
  });

  final TrackSource source;
  final SearchView view;
  final String keyword;
  final int page;

  /// 推荐与音源、关键词和页码无关。
  String get cacheKey => view == SearchView.recommend
      ? 'recommend'
      : '${source.name}|${view.name}|$page|$keyword';

  SearchQuery withPage(int page) {
    return SearchQuery(
      source: source,
      view: view,
      keyword: keyword,
      page: page,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SearchQuery &&
        other.source == source &&
        other.view == view &&
        other.keyword == keyword &&
        other.page == page;
  }

  @override
  int get hashCode => Object.hash(source, view, keyword, page);
}

sealed class SearchStatus {
  const SearchStatus();
}

final class SearchIdle extends SearchStatus {
  const SearchIdle();
}

final class SearchLoading extends SearchStatus {
  const SearchLoading();
}

final class SearchLoaded extends SearchStatus {
  const SearchLoaded();
}

/// 什么也没有加载到。[code] 是协议或本地错误码，完全没有收到回复时为 null。
final class SearchFailed extends SearchStatus {
  const SearchFailed({required this.code, required this.message});

  final String? code;
  final String message;
}

/// 已显示部分结果，其余失败：总览的两个列表之一失败，或下一页加载失败。
final class SearchPartial extends SearchStatus {
  const SearchPartial({required this.code, required this.message});

  final String? code;
  final String message;
}

/// 缓存只存结果本身，不存结果之外的状态。
final class SearchResults {
  const SearchResults({
    this.tracks = const [],
    this.tracksTotal = 0,
    this.playlists = const [],
    this.playlistsTotal = 0,
    this.recommendations = const [],
  });

  static const empty = SearchResults();

  final List<TrackSummary> tracks;
  final int tracksTotal;
  final List<PlaylistSummary> playlists;
  final int playlistsTotal;
  final List<TrackSummary> recommendations;

  /// 没有条目的一页表示列表已到末尾，不论服务端给出的总数是多少。
  SearchResults append(SearchResults page) {
    return SearchResults(
      tracks: [...tracks, ...page.tracks],
      tracksTotal: page.tracks.isEmpty ? tracks.length : page.tracksTotal,
      playlists: [...playlists, ...page.playlists],
      playlistsTotal: page.playlists.isEmpty
          ? playlists.length
          : page.playlistsTotal,
      recommendations: recommendations,
    );
  }
}

final class SearchState {
  const SearchState({
    this.query = const SearchQuery(
      source: TrackSource.qq,
      view: SearchView.all,
      keyword: '',
      page: 1,
    ),
    this.status = const SearchIdle(),
    this.results = SearchResults.empty,
    this.recentSearches = const [],
  });

  final SearchQuery query;
  final SearchStatus status;
  final SearchResults results;
  final List<SearchRecord> recentSearches;

  String get keyword => query.keyword;
  TrackSource get source => query.source;
  SearchView get view => query.view;

  /// 最后加载的页码；[tracks] 和 [playlists] 也包含之前各页的内容。
  int get page => query.page;

  List<TrackSummary> get tracks => results.tracks;
  List<PlaylistSummary> get playlists => results.playlists;
  List<TrackSummary> get recommendations => results.recommendations;

  bool get loading => status is SearchLoading;
  bool get failed => status is SearchFailed || status is SearchPartial;

  String? get errorMessage => switch (status) {
    SearchFailed(:final message) || SearchPartial(:final message) => message,
    _ => null,
  };

  bool get hasMore => switch (view) {
    SearchView.tracks => results.tracks.length < results.tracksTotal,
    SearchView.playlists => results.playlists.length < results.playlistsTotal,
    SearchView.all || SearchView.recommend => false,
  };

  TrackSummary? get bestMatch => tracks.isEmpty ? null : tracks.first;

  List<TrackSummary> get overviewTracks =>
      tracks.skip(1).take(5).toList(growable: false);

  // 总览的歌单排成两行，每行两个。
  List<PlaylistSummary> get overviewPlaylists =>
      playlists.take(4).toList(growable: false);

  PlaylistSummary? playlistSummary(TrackSource source, String id) {
    for (final playlist in playlists) {
      if (playlist.source == source && playlist.id == id) return playlist;
    }
    return null;
  }

  SearchState copyWith({
    SearchQuery? query,
    SearchStatus? status,
    SearchResults? results,
    List<SearchRecord>? recentSearches,
  }) {
    return SearchState(
      query: query ?? this.query,
      status: status ?? this.status,
      results: results ?? this.results,
      recentSearches: recentSearches ?? this.recentSearches,
    );
  }
}
