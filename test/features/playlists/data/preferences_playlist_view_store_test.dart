import 'package:alisten/domain/playlist/playlist_sort.dart';
import 'package:alisten/features/playlists/data/preferences_playlist_view_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';

Future<PreferencesPlaylistViewStore> _store([String? stored]) async {
  final preferences = await loadPreferences({
    PreferencesPlaylistViewStore.key: ?stored,
  });
  return PreferencesPlaylistViewStore(preferences);
}

void main() {
  test('nothing stored or something broken gives the defaults', () async {
    for (final stored in [null, '', '{', '[]', '"grid"']) {
      expect(
        (await _store(stored)).read(),
        PlaylistViewPreference.standard,
        reason: stored,
      );
    }
  });

  test('values it does not know fall back item by item', () async {
    final preference = (await _store(
      '{"view":"cards","sort":{"key":"name","order":"sideways"}}',
    )).read();

    expect(preference.view, PlaylistView.grid);
    expect(preference.sort.key, PlaylistSortKey.name);
    expect(preference.sort.order, SortOrder.descending);
  });

  test('reads what Web writes', () async {
    final preference = (await _store(
      '{"view":"list","sort":{"key":"trackCount","order":"asc"}}',
    )).read();

    expect(preference.view, PlaylistView.list);
    expect(
      preference.sort,
      const PlaylistSort(PlaylistSortKey.trackCount, SortOrder.ascending),
    );
  });

  test('writes the same JSON under the same key as Web', () async {
    final preferences = await loadPreferences();
    final store = PreferencesPlaylistViewStore(preferences);

    await store.write(
      const PlaylistViewPreference(
        view: PlaylistView.list,
        sort: PlaylistSort(PlaylistSortKey.createdAt, SortOrder.descending),
      ),
    );

    expect(
      preferences.getString('alisten.playlists-view'),
      '{"view":"list","sort":{"key":"createdAt","order":"desc"}}',
    );
  });
}
