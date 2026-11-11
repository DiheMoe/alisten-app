import 'package:alisten/domain/playlist/playlist_sort.dart';
import 'package:alisten/features/playlists/application/playlist_view_controller.dart';
import 'package:alisten/features/playlists/data/preferences_playlist_view_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';

final class _BrokenStore implements PlaylistViewStore {
  @override
  PlaylistViewPreference read() => PlaylistViewPreference.standard;

  @override
  Future<void> write(PlaylistViewPreference preference) async {
    throw Exception('disk full');
  }
}

void main() {
  test('changes are kept, and a new key starts with its own '
      'direction', () async {
    final preferences = await loadPreferences();
    final container = ProviderContainer(
      overrides: [
        playlistViewStoreProvider.overrideWithValue(
          PreferencesPlaylistViewStore(preferences),
        ),
      ],
    );
    addTearDown(container.dispose);
    final view = container.read(playlistViewProvider.notifier);

    view.setView(PlaylistView.list);
    view.setSortKey(PlaylistSortKey.name);
    expect(
      container.read(playlistViewProvider).sort,
      const PlaylistSort(PlaylistSortKey.name, SortOrder.ascending),
    );
    view.reverse();
    await pumpEventQueue();

    expect(
      container.read(playlistViewProvider),
      const PlaylistViewPreference(
        view: PlaylistView.list,
        sort: PlaylistSort(PlaylistSortKey.name, SortOrder.descending),
      ),
    );
    expect(
      PreferencesPlaylistViewStore(preferences).read(),
      container.read(playlistViewProvider),
    );

    view.setSortKey(PlaylistSortKey.name);
    expect(
      container.read(playlistViewProvider).sort.order,
      SortOrder.descending,
      reason: 'the same key keeps its direction',
    );
  });

  test('a preference that cannot be written still applies now', () async {
    final container = ProviderContainer(
      overrides: [playlistViewStoreProvider.overrideWithValue(_BrokenStore())],
    );
    addTearDown(container.dispose);

    container.read(playlistViewProvider.notifier).setView(PlaylistView.list);
    await pumpEventQueue();

    expect(container.read(playlistViewProvider).view, PlaylistView.list);
  });
}
