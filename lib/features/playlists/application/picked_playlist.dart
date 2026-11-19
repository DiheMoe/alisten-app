import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playlists/application/playlist_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 点歌页“我的歌单”里最近选的歌单，本次运行内有效。歌单只属于原来的服务器
/// 和账号，换了就忘掉。
final pickedPlaylistProvider = NotifierProvider<PickedPlaylist, String?>(
  PickedPlaylist.new,
);

final class PickedPlaylist extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(playlistApiProvider);
    ref.watch(
      identityControllerProvider.select((identity) => identity.session),
    );
    return null;
  }

  void pick(String id) => state = id;
}
