import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/application/playlist_api.dart';
import 'package:alisten/features/playlists/application/playlist_requests.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _notFound = 'NOT_FOUND';

@immutable
final class SharedPlaylistState {
  const SharedPlaylistState({this.playlist, this.expired = false, this.error});

  final SharedPlaylist? playlist;

  /// 歌单被删除了，或者分享的人停止了分享。
  final bool expired;
  final String? error;

  bool get loading => playlist == null && !expired && error == null;
}

final sharedPlaylistControllerProvider = NotifierProvider.autoDispose
    .family<SharedPlaylistController, SharedPlaylistState, String>(
      SharedPlaylistController.new,
    );

/// 不依赖身份：游客和还没有任何身份的新装 App 都能读。
final class SharedPlaylistController extends Notifier<SharedPlaylistState> {
  SharedPlaylistController(this.shareId);

  final String shareId;
  int _generation = 0;

  // 换服务器时 Riverpod 复用同一个实例重新 build，ref.mounted 一直是 true；
  // 只有 onDispose 在重新 build 之前执行，借它作废之前发起的读取。
  int _scope = 0;

  // 打开页面时的服务器。不在 onDispose 里重置：重新 build 时要拿它和新的比较。
  PlaylistApi? _origin;

  @override
  SharedPlaylistState build() {
    ref.onDispose(() => _scope++);
    final api = ref.watch(playlistApiProvider);
    // 分享 ID 只属于签发它的服务器，换了服务器就不再拿它去问新的服务器。
    if (!identical(_origin ??= api, api)) {
      return const SharedPlaylistState(expired: true);
    }
    unawaited(Future.microtask(load));
    return const SharedPlaylistState();
  }

  /// 重试就是重新读取，只有最后发起的那次能写入。
  Future<void> load() async {
    if (!ref.mounted) return;
    final scope = _currentScope;
    if (!_onOrigin) return;
    final generation = ++_generation;
    final api = ref.read(playlistApiProvider);
    state = const SharedPlaylistState();
    SharedPlaylistState next;
    try {
      next = SharedPlaylistState(playlist: await api.shared(shareId));
    } on ApiException catch (error) {
      next = error.code == _notFound
          ? const SharedPlaylistState(expired: true)
          : SharedPlaylistState(
              error: error.rateLimited ? rateLimitedText(error) : error.message,
            );
    } on Object catch (error) {
      AppLog.warn(
        'playlists',
        'shared playlist not read',
        type: '${error.runtimeType}',
      );
      next = const SharedPlaylistState(error: unexpectedFailureText);
    }
    if (_isCurrent(scope) && generation == _generation) state = next;
  }

  /// 复制到我的歌单。换了服务器时不发出。
  Future<MutationResult<MyPlaylist>> copy(String name) async {
    if (!_onOrigin) return const MutationNotSent(serverChangedNotice);
    final list = ref.read(myPlaylistsControllerProvider.notifier);
    return list.copyShared(shareId, name);
  }

  bool get _onOrigin => identical(ref.read(playlistApiProvider), _origin);

  // 读取 state 会先刷新过期的依赖，换服务器的通知在这一步送到。
  int get _currentScope {
    state;
    return _scope;
  }

  bool _isCurrent(int scope) => ref.mounted && scope == _currentScope;
}
