import 'dart:async';

import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/application/shared_playlist_controller.dart';
import 'package:alisten/features/playlists/presentation/playlist_header.dart';
import 'package:alisten/features/playlists/presentation/playlist_name_form.dart';
import 'package:alisten/features/playlists/presentation/playlist_song.dart';
import 'package:alisten/features/playlists/presentation/playlist_states.dart';
import 'package:alisten/features/playlists/presentation/save_to_playlist_sheet.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _notFound = 'NOT_FOUND';

/// 不需要身份就能读。自己分享的歌单打开后也是这个页面，与 Web 相同。
class SharedPlaylistScreen extends ConsumerWidget {
  const SharedPlaylistScreen({
    required this.shareId,
    required this.onResult,
    required this.onNotice,
    required this.onCopyTitle,
    required this.onOpenAccount,
    super.key,
  });

  final String shareId;
  final QueueResultCallback onResult;
  final PlaylistNotice onNotice;
  final ValueChanged<String> onCopyTitle;
  final VoidCallback onOpenAccount;

  Future<void> _copy(BuildContext context, SharedPlaylist shared) async {
    final notice = onNotice;
    final container = ProviderScope.containerOf(context);
    final provider = sharedPlaylistControllerProvider(shareId);
    // 复制经过分享页的控制器：shareId 是原来的服务器签发的，换了服务器就不能
    // 再发出去。
    final page = container.read(provider.notifier);
    // 页面不监听列表控制器，也可能先于面板离开：两个控制器都由这里持有，否则
    // 先取到的控制器会在面板开始监听之前被释放，随之失效。
    final holdList = container.listen(myPlaylistsControllerProvider, (_, _) {});
    final holdPage = container.listen(provider, (_, _) {});
    final MyPlaylist? copied;
    try {
      copied = await showPlaylistNameSheet<MyPlaylist>(
        context,
        title: '复制到我的歌单',
        initialName: shared.name,
        confirmLabel: '复制',
        busyLabel: '正在复制…',
        guestMessage: '注册或登录之后就能把这个歌单复制到自己的歌单。',
        onOpenAccount: onOpenAccount,
        onSubmit: (name) async {
          final result = await page.copy(name);
          // 分享刚刚失效：面板下方显示服务端消息，页面还在时重新读取，变成
          // “分享已失效”。
          if (result case MutationFailed(code: _notFound)
              when context.mounted) {
            unawaited(page.load());
          }
          return result;
        },
      );
    } finally {
      holdList.close();
      holdPage.close();
    }
    if (copied == null) return;
    notice(ToastKind.success, '已复制为“${copied.name}”，共 ${copied.trackCount} 首');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(sharedPlaylistControllerProvider(shareId));
    final shared = page.playlist;
    final error = page.error;
    final media = MediaQuery.paddingOf(context);
    final List<Widget> slivers;
    if (page.expired) {
      slivers = [
        const PlaylistPageFill(
          child: EmptyState(
            icon: Icons.link_off_rounded,
            title: '分享已失效',
            message: '歌单被删除了，或者分享的人停止了分享。',
          ),
        ),
      ];
    } else if (error != null) {
      slivers = [
        PlaylistPageFill(
          child: PlaylistReadFailure(
            message: error,
            onRetry: () => unawaited(
              ref
                  .read(sharedPlaylistControllerProvider(shareId).notifier)
                  .load(),
            ),
          ),
        ),
      ];
    } else if (shared == null) {
      slivers = [const PlaylistPageFill(child: PlaylistLoading())];
    } else {
      slivers = [
        SliverToBoxAdapter(child: _header(context, shared)),
        if (shared.items.isEmpty)
          SliverFillRemaining(
            child: Padding(
              padding: EdgeInsets.only(bottom: media.bottom),
              child: const EmptyState(
                icon: Icons.queue_music_rounded,
                title: '这个歌单还是空的',
              ),
            ),
          )
        else ...[
          const SliverToBoxAdapter(child: PickUnavailableNotice()),
          SliverList.builder(
            itemCount: shared.items.length,
            itemBuilder: (context, index) {
              final item = shared.items[index];
              final meta = item.meta;
              return TrackRow(
                key: ValueKey(trackKey(item.track)),
                title: meta.title,
                subtitle: playlistSongSubtitle(meta),
                coverUrl: meta.coverUrl,
                onLongPress: () => onCopyTitle(meta.title),
                longPressHint: copyTitleHint,
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AlistenSpacing.page,
                  AlistenSpacing.xxs,
                  AlistenSpacing.xs,
                  AlistenSpacing.xxs,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 点歌结果写出来时要两百多 dp，3 倍字号下会挤掉保存按钮。结果另
                    // 作为按钮的值读出。
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 2,
                      child: PlaylistPickControl(
                        track: item.track,
                        title: meta.title,
                        onPick: (track, title) =>
                            unawaited(pickSong(ref, onResult, track, title)),
                      ),
                    ),
                    SaveToPlaylistButton(
                      track: item.track,
                      title: meta.title,
                      onOpenAccount: onOpenAccount,
                      onNotice: onNotice,
                      iconSize: AlistenSizes.iconSm,
                    ),
                  ],
                ),
              );
            },
          ),
          SliverPadding(
            padding: EdgeInsets.only(bottom: media.bottom + AlistenSpacing.xl),
          ),
        ],
      ];
    }
    return AlistenScaffold(
      body: Stack(
        children: [
          CustomScrollView(slivers: slivers),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AlistenTopBar(
              leading: IconCircleButton(
                icon: Icons.arrow_back_rounded,
                semanticLabel: '返回',
                onPressed: () => unawaited(Navigator.maybePop(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, SharedPlaylist shared) {
    final colors = AlistenColors.of(context);
    return PlaylistHeader(
      coverUrl: shared.coverUrl,
      favorites: shared.favorites,
      name: shared.name,
      children: [
        const SizedBox(height: AlistenSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MemberAvatar(
              name: shared.ownerName,
              imageUrl: avatarUrlFor(
                shared.ownerAvatarHash,
                AlistenSizes.memberTag,
              ),
              size: AlistenSizes.memberTag,
            ),
            const SizedBox(width: AlistenSpacing.xxs),
            Flexible(
              child: Text(
                '${shared.ownerName} 分享，${shared.items.length} 首',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AlistenTypography.secondary.copyWith(
                  color: colors.onGlassMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AlistenSpacing.md),
        Center(
          child: PillButton(
            label: '复制到我的歌单',
            icon: Icons.library_add_rounded,
            onPressed: () => unawaited(_copy(context, shared)),
          ),
        ),
      ],
    );
  }
}
