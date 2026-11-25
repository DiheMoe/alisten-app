import 'dart:async';

import 'package:alisten/app/feedback.dart';
import 'package:alisten/app/room/connection_pill.dart';
import 'package:alisten/app/room/room_actions.dart';
import 'package:alisten/features/chat/index.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 桌面窗口里房间页的中间部分：顶上是点歌和房间操作，下面是封面和歌词。队列、
/// 聊天和播放条由窗口骨架常驻显示。
class DesktopRoomStage extends ConsumerWidget {
  const DesktopRoomStage({required this.roomRef, super.key});

  final String roomRef;

  static const _barHeight = 64.0;
  static const _minLyricsWidth = 320.0;

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final room = ref.read(roomControllerProvider.notifier);
    if (!await confirmLeavingRoom(context)) return;
    router.go('/');
    unawaited(room.leaveRoom());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    final room = ref.watch(
      roomControllerProvider.select((room) {
        final snapshot = room.snapshot;
        final id = room.activeRoomId;
        if (snapshot == null || id == null) return null;
        return (
          id: id,
          slug: room.roomSlug,
          name: snapshot.room.name,
          cover: snapshot.nowPlaying?.entry.meta.coverUrl,
          status: room.status,
          nextRetryAt: room.nextRetryAt,
          mayReconnectNow: room.mayReconnectNow,
        );
      }),
    );
    if (room == null) return const SizedBox.shrink();
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          SizedBox(
            height: _barHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlistenSpacing.lg,
              ),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AlistenTypography.title.copyWith(
                        color: colors.onGlass,
                      ),
                    ),
                  ),
                  const SizedBox(width: AlistenSpacing.sm),
                  ConnectionPill(
                    status: room.status,
                    nextRetryAt: room.nextRetryAt,
                    onRetryNow: room.mayReconnectNow
                        ? () => unawaited(
                            ref
                                .read(roomControllerProvider.notifier)
                                .checkConnection(),
                          )
                        : null,
                  ),
                  const SizedBox(width: AlistenSpacing.sm),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _SearchEntry(
                        onPressed: () =>
                            unawaited(context.push<void>('/r/$roomRef/search')),
                      ),
                    ),
                  ),
                  const SizedBox(width: AlistenSpacing.xs),
                  _Action(
                    icon: AlistenIcons.playlist,
                    label: '从歌单点歌',
                    onPressed: () => unawaited(
                      context.push<void>('/r/$roomRef/from-playlists'),
                    ),
                  ),
                  const SizedBox(width: AlistenSpacing.md),
                  _Action(
                    icon: AlistenIcons.userPlus,
                    label: '复制邀请链接',
                    onPressed: () =>
                        copyInviteLink(ref, id: room.id, slug: room.slug),
                  ),
                  const SizedBox(width: AlistenSpacing.xs),
                  _Action(
                    icon: AlistenIcons.signOut,
                    label: '退出房间',
                    onPressed: () => unawaited(_leave(context, ref)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final coverSize = (constraints.maxHeight * 0.52).clamp(
                  160.0,
                  300.0,
                );
                // 窄窗口里只留歌词。
                final showCover =
                    constraints.maxWidth >=
                    coverSize + _minLyricsWidth + 3 * AlistenSpacing.xxl;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AlistenSpacing.xxl,
                    0,
                    AlistenSpacing.md,
                    AlistenSpacing.md,
                  ),
                  child: Row(
                    children: [
                      if (showCover) ...[
                        CoverArt(
                          url: room.cover,
                          size: coverSize,
                          radius: AlistenRadii.lg,
                          shadow: true,
                        ),
                        const SizedBox(width: AlistenSpacing.xxl),
                      ],
                      const Expanded(child: LyricsView()),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 看起来是输入框，点下去打开点歌页并聚焦到它的输入框。
class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onPressed});

  final VoidCallback onPressed;

  static const _maxWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: '搜歌',
        focusRadius: BorderRadius.circular(AlistenRadii.pill),
        child: Container(
          height: AlistenSizes.iconButton,
          padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.md),
          decoration: BoxDecoration(
            color: colors.raised,
            borderRadius: BorderRadius.circular(AlistenRadii.pill),
            border: Border.all(
              color: colors.glassStroke,
              width: AlistenSizes.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                AlistenIcons.magnifyingGlass,
                size: AlistenSizes.iconSm,
                color: colors.onGlassMuted,
              ),
              const SizedBox(width: AlistenSpacing.xs),
              Expanded(
                child: Text(
                  '搜歌名、歌手，或粘贴链接',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlassMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 只有图标的按钮：名称在悬停提示里，读屏照常读出。
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: IconCircleButton(
        icon: icon,
        semanticLabel: label,
        onPressed: onPressed,
      ),
    );
  }
}

/// 所在房间的队列和聊天，同时显示。
class DesktopRoomPanel extends ConsumerWidget {
  const DesktopRoomPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    final toasts = ref.read(toastControllerProvider);
    final router = GoRouter.of(context);
    void openAccount() => router.go('/settings/account');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        0,
        AlistenSpacing.sm,
        AlistenSpacing.sm,
        AlistenSpacing.sm,
      ),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        radius: AlistenRadii.md,
        child: QueueCoverWarmup(
          child: Column(
            children: [
              Expanded(
                flex: 5,
                child: QueueView(
                  onResult: (result, success) =>
                      reportMutation(toasts, result, success: (_) => success),
                  onCopyTitle: (title) => copySongTitle(toasts, title),
                  onSaveToPlaylist: (context, track, title) => unawaited(
                    showSaveToPlaylistSheet(
                      context,
                      SaveOneTrack(track: track, title: title),
                      onOpenAccount: openAccount,
                      onNotice: toasts.show,
                    ),
                  ),
                ),
              ),
              Container(
                height: AlistenSizes.hairline,
                margin: const EdgeInsets.symmetric(
                  horizontal: AlistenSpacing.md,
                ),
                color: colors.onGlass.withValues(alpha: 0.08),
              ),
              const Expanded(flex: 4, child: ChatView()),
            ],
          ),
        ),
      ),
    );
  }
}
