import 'dart:convert';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/playlist/playlist_sort.dart';
import 'package:alisten/features/playlists/application/playlist_view_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _views = {'grid': PlaylistView.grid, 'list': PlaylistView.list};
const _keys = {
  'name': PlaylistSortKey.name,
  'createdAt': PlaylistSortKey.createdAt,
  'updatedAt': PlaylistSortKey.updatedAt,
  'trackCount': PlaylistSortKey.trackCount,
};
const _orders = {'asc': SortOrder.ascending, 'desc': SortOrder.descending};

/// 键名和格式与 Web 的 localStorage 相同。
final class PreferencesPlaylistViewStore implements PlaylistViewStore {
  const PreferencesPlaylistViewStore(this._preferences);

  static const key = 'alisten.playlists-view';

  final SharedPreferences _preferences;

  @override
  PlaylistViewPreference read() {
    const fallback = PlaylistViewPreference.standard;
    final Object? json;
    try {
      json = jsonDecode(_preferences.getString(key) ?? '');
    } on Object {
      return fallback;
    }
    if (json is! Map<String, Object?>) return fallback;
    final sort = json['sort'];
    final sortJson = sort is Map<String, Object?>
        ? sort
        : const <String, Object?>{};
    return PlaylistViewPreference(
      view: _views[json['view']] ?? fallback.view,
      sort: PlaylistSort(
        _keys[sortJson['key']] ?? fallback.sort.key,
        _orders[sortJson['order']] ?? fallback.sort.order,
      ),
    );
  }

  @override
  Future<void> write(PlaylistViewPreference preference) async {
    final saved = await _preferences.setString(
      key,
      jsonEncode({
        'view': preference.view.name,
        'sort': {
          'key': preference.sort.key.name,
          'order': preference.sort.order == SortOrder.ascending
              ? 'asc'
              : 'desc',
        },
      }),
    );
    if (!saved) AppLog.warn('playlists', 'view preference not written');
  }
}
