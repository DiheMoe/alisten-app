import 'dart:async';

import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/application/playlist_api.dart';
import 'package:alisten/features/playlists/presentation/playlist_name_form.dart';
import 'package:alisten/features/playlists/presentation/playlist_states.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [name] 是搜索结果里的歌单名；从链接直接打开时没有摘要，调用方传“导入的歌单”。
class SavePlatformPlaylistButton extends StatelessWidget {
  const SavePlatformPlaylistButton({
    required this.source,
    required this.playlistId,
    required this.name,
    required this.onOpenAccount,
    required this.onNotice,
    super.key,
  });

  final TrackSource source;
  final String playlistId;
  final String name;
  final VoidCallback onOpenAccount;
  final PlaylistNotice onNotice;

  Future<void> _save(BuildContext context) async {
    final notice = onNotice;
    final container = ProviderScope.containerOf(context);
    final list = container.read(myPlaylistsControllerProvider.notifier);
    // 这个页面不监听列表控制器：不在这里持有，它会在面板开始监听之前被释放，
    // 先取到的控制器随之失效。
    final hold = container.listen(myPlaylistsControllerProvider, (_, _) {});
    final ImportedPlaylist? saved;
    try {
      saved = await showPlaylistNameSheet<ImportedPlaylist>(
        context,
        title: '保存为我的歌单',
        initialName: name,
        confirmLabel: '保存',
        busyLabel: '正在保存…',
        guestMessage: '注册或登录之后就能保存这个歌单。',
        onOpenAccount: onOpenAccount,
        onSubmit: (name) => list.importPlatform(
          source: source,
          playlistId: playlistId,
          name: name,
        ),
      );
    } finally {
      hold.close();
    }
    if (saved == null) return;
    notice(
      ToastKind.success,
      '已保存为“${saved.playlist.name}”，共 ${saved.imported} 首',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PillButton(
      label: '保存为我的歌单',
      icon: Icons.playlist_add_rounded,
      style: PillButtonStyle.secondary,
      onPressed: () => unawaited(_save(context)),
    );
  }
}
