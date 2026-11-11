import 'dart:math' as math;

import 'package:alisten/domain/playlist/my_playlist.dart';

enum PlaylistSortKey { name, createdAt, updatedAt, trackCount }

enum SortOrder { ascending, descending }

final class PlaylistSort {
  const PlaylistSort(this.key, this.order);

  final PlaylistSortKey key;
  final SortOrder order;

  @override
  bool operator ==(Object other) =>
      other is PlaylistSort && other.key == key && other.order == order;

  @override
  int get hashCode => Object.hash(key, order);
}

enum PlaylistView { grid, list }

final class PlaylistViewPreference {
  const PlaylistViewPreference({required this.view, required this.sort});

  static const standard = PlaylistViewPreference(
    view: PlaylistView.grid,
    sort: PlaylistSort(PlaylistSortKey.updatedAt, SortOrder.descending),
  );

  final PlaylistView view;
  final PlaylistSort sort;

  PlaylistViewPreference copyWith({PlaylistView? view, PlaylistSort? sort}) {
    return PlaylistViewPreference(
      view: view ?? this.view,
      sort: sort ?? this.sort,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaylistViewPreference &&
      other.view == view &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(view, sort);
}

SortOrder defaultOrder(PlaylistSortKey key) =>
    key == PlaylistSortKey.name ? SortOrder.ascending : SortOrder.descending;

/// “我喜欢”始终在最前，不参与排序。方向作用于整个比较（包括用来分出先后的
/// 创建时间和 ID），所以反向得到的正好是倒过来的列表。
List<MyPlaylist> sortPlaylists(List<MyPlaylist> playlists, PlaylistSort sort) {
  final rest = [
    for (final playlist in playlists)
      if (!playlist.favorites) playlist,
  ];
  rest.sort((a, b) {
    final compared = _compare(a, b, sort.key);
    return sort.order == SortOrder.ascending ? compared : -compared;
  });
  return [
    for (final playlist in playlists)
      if (playlist.favorites) playlist,
    ...rest,
  ];
}

int _compare(MyPlaylist a, MyPlaylist b, PlaylistSortKey key) {
  final compared = switch (key) {
    PlaylistSortKey.name => compareNames(a.name, b.name),
    PlaylistSortKey.createdAt => a.createdAtMs.compareTo(b.createdAtMs),
    PlaylistSortKey.updatedAt => a.updatedAtMs.compareTo(b.updatedAtMs),
    PlaylistSortKey.trackCount => a.trackCount.compareTo(b.trackCount),
  };
  if (compared != 0) return compared;
  final created = a.createdAtMs.compareTo(b.createdAtMs);
  return created != 0 ? created : a.id.compareTo(b.id);
}

final _nameChunk = RegExp(r'\d+|\D', unicode: true);
final _digits = RegExp(r'^\d+$');

List<String> _chunks(String name) => [
  for (final match in _nameChunk.allMatches(name.toLowerCase())) match[0]!,
];

/// 不区分大小写，连续的数字按数值比较，其余按 Unicode 码点比较。Web 按拼音排
/// 中文；Dart 没有内置的排序规则，为此引入依赖不值得。
int compareNames(String a, String b) {
  final left = _chunks(a);
  final right = _chunks(b);
  for (var index = 0; index < math.min(left.length, right.length); index++) {
    final x = left[index];
    final y = right[index];
    final compared = _digits.hasMatch(x) && _digits.hasMatch(y)
        ? BigInt.parse(x).compareTo(BigInt.parse(y))
        : x.runes.first.compareTo(y.runes.first);
    if (compared != 0) return compared;
  }
  return left.length.compareTo(right.length);
}

String sortKeyLabel(PlaylistSortKey key) => switch (key) {
  PlaylistSortKey.name => '名称',
  PlaylistSortKey.createdAt => '创建时间',
  PlaylistSortKey.updatedAt => '更新时间',
  PlaylistSortKey.trackCount => '歌曲数',
};

String sortOrderLabel(PlaylistSort sort) {
  final ascending = sort.order == SortOrder.ascending;
  return switch (sort.key) {
    PlaylistSortKey.name => ascending ? 'A–Z' : 'Z–A',
    PlaylistSortKey.createdAt ||
    PlaylistSortKey.updatedAt => ascending ? '最早在前' : '最新在前',
    PlaylistSortKey.trackCount => ascending ? '最少在前' : '最多在前',
  };
}
