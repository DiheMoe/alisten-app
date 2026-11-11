import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/playlist/playlist_sort.dart';
import 'package:flutter_test/flutter_test.dart';

MyPlaylist _playlist(
  String id, {
  String? name,
  bool favorites = false,
  int created = 1,
  int updated = 1,
  int count = 0,
}) {
  return MyPlaylist(
    id: id,
    name: name ?? id,
    favorites: favorites,
    trackCount: count,
    createdAtMs: created,
    updatedAtMs: updated,
  );
}

final _favorites = _playlist(
  'fav',
  name: '我喜欢',
  favorites: true,
  created: 50,
  updated: 1,
  count: 0,
);

List<String> _ids(List<MyPlaylist> playlists) => [
  for (final playlist in playlists) playlist.id,
];

void main() {
  final playlists = [
    _playlist('b', name: 'Beta', created: 3, updated: 30, count: 5),
    _favorites,
    _playlist('a', name: 'alpha', created: 2, updated: 10, count: 9),
    _playlist('c', name: 'Gamma', created: 1, updated: 20, count: 1),
  ];

  test('favorites come first under every key and direction', () {
    for (final key in PlaylistSortKey.values) {
      for (final order in SortOrder.values) {
        expect(
          sortPlaylists(playlists, PlaylistSort(key, order)).first.id,
          'fav',
          reason: '$key $order',
        );
      }
    }
  });

  test('each key orders by its own value', () {
    expect(
      _ids(
        sortPlaylists(
          playlists,
          const PlaylistSort(PlaylistSortKey.name, SortOrder.ascending),
        ),
      ),
      ['fav', 'a', 'b', 'c'],
    );
    expect(
      _ids(
        sortPlaylists(
          playlists,
          const PlaylistSort(PlaylistSortKey.createdAt, SortOrder.ascending),
        ),
      ),
      ['fav', 'c', 'a', 'b'],
    );
    expect(
      _ids(
        sortPlaylists(
          playlists,
          const PlaylistSort(PlaylistSortKey.updatedAt, SortOrder.descending),
        ),
      ),
      ['fav', 'b', 'c', 'a'],
    );
    expect(
      _ids(
        sortPlaylists(
          playlists,
          const PlaylistSort(PlaylistSortKey.trackCount, SortOrder.descending),
        ),
      ),
      ['fav', 'a', 'b', 'c'],
    );
  });

  test('ties fall back to the creation time, then the id', () {
    final tied = [
      _playlist('y', count: 2, created: 5),
      _playlist('x', count: 2, created: 5),
      _playlist('w', count: 2, created: 4),
    ];

    expect(
      _ids(
        sortPlaylists(
          tied,
          const PlaylistSort(PlaylistSortKey.trackCount, SortOrder.ascending),
        ),
      ),
      ['w', 'x', 'y'],
    );
  });

  test('the other direction is exactly the reverse, favorites aside', () {
    for (final key in PlaylistSortKey.values) {
      final up = sortPlaylists(
        playlists,
        PlaylistSort(key, SortOrder.ascending),
      );
      final down = sortPlaylists(
        playlists,
        PlaylistSort(key, SortOrder.descending),
      );
      expect(
        _ids(down.skip(1).toList()),
        _ids(up.skip(1).toList().reversed.toList()),
        reason: '$key',
      );
    }
  });

  test('names ignore case and compare runs of digits by value', () {
    expect(compareNames('歌单 2', '歌单 10'), lessThan(0));
    expect(compareNames('track9', 'track10'), lessThan(0));
    expect(compareNames('abc', 'ABD'), lessThan(0));
    expect(compareNames('B', 'a'), greaterThan(0));
    expect(compareNames('Mix', 'mix'), 0);
    expect(compareNames('歌单', '歌单 1'), lessThan(0));
    expect(
      compareNames('歌单 99999999999999999999', '歌单 100000000000000000000'),
      lessThan(0),
    );
  });

  test('names equal but for case tie, then fall back to the creation time '
      'and the id', () {
    final tied = [
      _playlist('m0', name: 'mix', created: 2),
      _playlist('m2', name: 'Mix', created: 1),
      _playlist('m1', name: 'MIX', created: 2),
    ];

    expect(
      _ids(
        sortPlaylists(
          tied,
          const PlaylistSort(PlaylistSortKey.name, SortOrder.ascending),
        ),
      ),
      ['m2', 'm0', 'm1'],
    );
  });

  test('an empty list stays empty', () {
    expect(
      sortPlaylists(
        const [],
        const PlaylistSort(PlaylistSortKey.name, SortOrder.ascending),
      ),
      isEmpty,
    );
  });

  test('Chinese names are in code point order, not pinyin', () {
    // 一 是 U+4E00，丁 是 U+4E01。
    expect(compareNames('一', '丁'), lessThan(0));
    expect(compareNames('😀', '\u{FFFD}'), greaterThan(0));
  });

  test('a name sorts ascending by default, every other key descending', () {
    expect(defaultOrder(PlaylistSortKey.name), SortOrder.ascending);
    expect(defaultOrder(PlaylistSortKey.createdAt), SortOrder.descending);
    expect(defaultOrder(PlaylistSortKey.updatedAt), SortOrder.descending);
    expect(defaultOrder(PlaylistSortKey.trackCount), SortOrder.descending);
    expect(PlaylistViewPreference.standard.view, PlaylistView.grid);
    expect(
      PlaylistViewPreference.standard.sort,
      const PlaylistSort(PlaylistSortKey.updatedAt, SortOrder.descending),
    );
  });

  test('keys and directions are named like Web', () {
    expect(
      [for (final key in PlaylistSortKey.values) sortKeyLabel(key)],
      ['名称', '创建时间', '更新时间', '歌曲数'],
    );
    String label(PlaylistSortKey key, SortOrder order) =>
        sortOrderLabel(PlaylistSort(key, order));
    expect(label(PlaylistSortKey.name, SortOrder.ascending), 'A–Z');
    expect(label(PlaylistSortKey.name, SortOrder.descending), 'Z–A');
    expect(label(PlaylistSortKey.createdAt, SortOrder.ascending), '最早在前');
    expect(label(PlaylistSortKey.updatedAt, SortOrder.descending), '最新在前');
    expect(label(PlaylistSortKey.trackCount, SortOrder.ascending), '最少在前');
    expect(label(PlaylistSortKey.trackCount, SortOrder.descending), '最多在前');
  });
}
