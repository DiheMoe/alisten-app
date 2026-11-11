import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ImportedPlaylist = ({MyPlaylist playlist, int imported});

/// 实现绑定在创建时的服务器上，需要成员身份的接口自己读取 memberToken；调用方
/// 不经手 token。只有 [shared] 不需要身份。
abstract interface class PlaylistApi {
  Future<List<MyPlaylist>> listMine();

  Future<MyPlaylist> create(String name);

  Future<void> rename(String id, String name);

  Future<void> delete(String id);

  /// 新加入的在前。
  Future<List<TrackSummary>> items(String id);

  Future<void> add(String id, Track track);

  Future<void> remove(String id, List<Track> tracks);

  /// 返回新加入的首数，已经在里面的歌不算。
  Future<int> copy({
    required String from,
    required String to,
    required List<Track> tracks,
  });

  /// 没有 [before] 时放到最后。
  Future<void> move(String id, List<Track> tracks, {Track? before});

  Future<Set<String>> containing(Track track);

  Future<ImportedPlaylist> importFile(
    String name,
    List<PlaylistFileTrack> tracks,
  );

  Future<({TrackSource source, String playlistId})> resolveLink(String link);

  Future<ImportedPlaylist> importPlatform({
    required String name,
    required TrackSource source,
    required String playlistId,
  });

  /// 每次都生成新的分享 ID，旧的随之失效。
  Future<String> share(String id);

  Future<void> unshare(String id);

  Future<SharedPlaylist> shared(String shareId);

  Future<MyPlaylist> copyShared(String shareId, String name);
}

final playlistApiProvider = Provider<PlaylistApi>((ref) {
  throw UnimplementedError('playlistApi 未注入');
});
