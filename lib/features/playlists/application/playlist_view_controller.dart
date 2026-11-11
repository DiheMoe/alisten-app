import 'dart:async';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/playlist/playlist_sort.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 显示偏好，不分服务器。[read] 不抛出，读不出的项取默认值。
abstract interface class PlaylistViewStore {
  PlaylistViewPreference read();

  Future<void> write(PlaylistViewPreference preference);
}

final playlistViewStoreProvider = Provider<PlaylistViewStore>((ref) {
  throw UnimplementedError('playlistViewStore 未注入');
});

final playlistViewProvider =
    NotifierProvider<PlaylistViewController, PlaylistViewPreference>(
      PlaylistViewController.new,
    );

final class PlaylistViewController extends Notifier<PlaylistViewPreference> {
  @override
  PlaylistViewPreference build() => ref.watch(playlistViewStoreProvider).read();

  void setView(PlaylistView view) => _change(state.copyWith(view: view));

  /// 换一个排序键时，方向改用这个键的默认方向。
  void setSortKey(PlaylistSortKey key) {
    if (key == state.sort.key) return;
    _change(state.copyWith(sort: PlaylistSort(key, defaultOrder(key))));
  }

  void reverse() {
    final sort = state.sort;
    _change(
      state.copyWith(
        sort: PlaylistSort(
          sort.key,
          sort.order == SortOrder.ascending
              ? SortOrder.descending
              : SortOrder.ascending,
        ),
      ),
    );
  }

  // 写入失败时本次运行仍按新的偏好显示。
  void _change(PlaylistViewPreference next) {
    state = next;
    unawaited(
      ref
          .read(playlistViewStoreProvider)
          .write(next)
          .then<void>(
            (_) {},
            onError: (Object error) => AppLog.warn(
              'playlists',
              'view preference not saved',
              type: '${error.runtimeType}',
            ),
          ),
    );
  }
}
