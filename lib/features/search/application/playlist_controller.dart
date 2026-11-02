import 'dart:async';

import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/search_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 同一个 id 可能同时存在于两个音源，所以用音源和 id 一起标识歌单。
final class PlaylistKey {
  const PlaylistKey(this.source, this.id);

  final TrackSource source;
  final String id;

  @override
  bool operator ==(Object other) {
    return other is PlaylistKey && other.source == source && other.id == id;
  }

  @override
  int get hashCode => Object.hash(source, id);
}

/// 服务端一次返回歌单的全部歌曲，不分页。
final class PlaylistDetail {
  const PlaylistDetail({required this.tracks});

  final List<TrackSummary> tracks;
}

/// 歌单无论连接状态如何都打不开。
final class PlaylistUnavailable implements Exception {
  const PlaylistUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

String playlistErrorMessage(Object error) {
  return switch (error) {
    PlaylistUnavailable(:final message) ||
    RoomRequestException(:final message) => message,
    _ => '歌单加载失败，请重试。',
  };
}

final playlistControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PlaylistController, PlaylistDetail, PlaylistKey>(
      PlaylistController.new,
      retry: (retryCount, error) => null,
    );

final class PlaylistController extends AsyncNotifier<PlaylistDetail> {
  PlaylistController(this.key);

  final PlaylistKey key;

  @override
  Future<PlaylistDetail> build() async {
    if (!canOpenPlaylists(key.source)) {
      throw const PlaylistUnavailable('该来源不支持歌单');
    }
    // 换房间即换连接，要丢弃这次构建，在新房间重新请求歌单。
    ref.watch(roomControllerProvider.select((state) => state.activeRoomId));
    if (!_open(ref.read(roomControllerProvider))) {
      // 连接打开之前一直显示加载中，例如启动时从链接打开歌单。只有这段等待
      // 跟随连接状态，已显示的歌单在重连期间保持不变。
      ref.watch(roomControllerProvider.select(_open));
      return Completer<PlaylistDetail>().future;
    }
    final tracks = await ref
        .read(roomControllerProvider.notifier)
        .query((c) => c.playlistTracks(source: key.source, playlistId: key.id));
    return PlaylistDetail(tracks: tracks);
  }

  void retry() => ref.invalidateSelf();

  static bool _open(RoomState room) {
    return room.status == RoomConnectionStatus.open;
  }
}
