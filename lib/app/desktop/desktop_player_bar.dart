import 'dart:async';

import 'package:alisten/app/feedback.dart';
import 'package:alisten/app/room/room_actions.dart';
import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_slider.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/playback_progress_bar.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 桌面窗口底部常驻的播放条：正在播放的歌、本机暂停、投票切歌、进度和音量。
class DesktopPlayerBar extends ConsumerStatefulWidget {
  const DesktopPlayerBar({super.key});

  static const height = 76.0;

  @override
  ConsumerState<DesktopPlayerBar> createState() => _DesktopPlayerBarState();
}

class _DesktopPlayerBarState extends ConsumerState<DesktopPlayerBar> {
  (PlaybackIdentity, VoteSkipResult)? _vote;
  PlaybackIdentity? _voting;

  Future<void> _voteSkip(PlaybackIdentity playback) async {
    final toasts = ref.read(toastControllerProvider);
    final actions = ref.read(queueActionsProvider);
    setState(() => _voting = playback);
    final result = await actions.voteSkip();
    reportVote(toasts, result);
    if (!mounted) return;
    setState(() {
      if (_voting == playback) _voting = null;
      if (result case MutationSucceeded(:final value) when !value.skipped) {
        _vote = (playback, value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final room = ref.watch(
      roomControllerProvider.select(
        (room) => (
          id: room.activeRoomId,
          slug: room.roomSlug,
          nowPlaying: room.snapshot?.nowPlaying,
          connected: room.status == RoomConnectionStatus.open,
        ),
      ),
    );
    final nowPlaying = room.nowPlaying;
    final connected = room.connected;
    final roomRef = room.slug ?? room.id;
    final router = GoRouter.of(context);
    final toasts = ref.read(toastControllerProvider);
    final openRoom = roomRef == null ? null : () => router.go('/r/$roomRef');
    final playback = nowPlaying == null
        ? null
        : PlaybackIdentity(
            entryId: nowPlaying.entry.id,
            startedAtMs: nowPlaying.startedAtMs,
          );
    // 每次播放只能投一票，换了歌才能再投。
    final vote = switch (_vote) {
      (final votedOn, final result) when votedOn == playback => result,
      _ => null,
    };
    return Container(
      height: DesktopPlayerBar.height,
      padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.md),
      decoration: BoxDecoration(
        color: colors.glassFill,
        border: Border(
          top: BorderSide(
            color: colors.onGlass.withValues(alpha: 0.08),
            width: AlistenSizes.hairline,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _Playing(nowPlaying: nowPlaying, onOpenRoom: openRoom),
          ),
          const SizedBox(width: AlistenSpacing.lg),
          Expanded(
            flex: 5,
            child: nowPlaying == null
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      PlayerControls(
                        compact: true,
                        vote: vote,
                        voting: playback != null && _voting == playback,
                        onVoteSkip: playback != null && connected
                            ? () => unawaited(_voteSkip(playback))
                            : null,
                      ),
                      const SizedBox(width: AlistenSpacing.sm),
                      const Expanded(child: _Progress()),
                    ],
                  ),
          ),
          const SizedBox(width: AlistenSpacing.lg),
          Expanded(
            flex: 3,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (nowPlaying != null) ...[
                    Tooltip(
                      message: '保存到歌单',
                      excludeFromSemantics: true,
                      child: SaveToPlaylistButton(
                        track: nowPlaying.entry.track,
                        title: nowPlaying.entry.meta.title,
                        onOpenAccount: () => router.go('/settings/account'),
                        onNotice: toasts.show,
                      ),
                    ),
                    const SizedBox(width: AlistenSpacing.xs),
                  ],
                  const _Volume(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Playing extends StatelessWidget {
  const _Playing({required this.nowPlaying, required this.onOpenRoom});

  final NowPlaying? nowPlaying;
  final VoidCallback? onOpenRoom;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final entry = nowPlaying?.entry;
    final Widget content;
    if (entry == null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AlistenIcons.musicNote,
            size: AlistenSizes.iconSm,
            color: colors.onGlassMuted,
          ),
          const SizedBox(width: AlistenSpacing.xs),
          Flexible(
            child: Text(
              '房间暂时没有播放',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AlistenTypography.secondary.copyWith(
                color: colors.onGlassMuted,
              ),
            ),
          ),
        ],
      );
    } else {
      final meta = entry.meta;
      final requester = entry.auto
          ? '自动推荐'
          : switch (entry.requestedBy) {
              final member? => '${member.name} 点歌',
              null => null,
            };
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoverArt(url: meta.coverUrl, size: 48),
          const SizedBox(width: AlistenSpacing.sm),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AlistenTypography.bodyStrong.copyWith(
                    color: colors.onGlass,
                  ),
                ),
                Text(
                  [
                    meta.artist,
                    ?requester,
                  ].where((part) => part.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlassMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Tooltip(
        message: '回到房间',
        excludeFromSemantics: true,
        child: Pressable(
          onPressed: onOpenRoom,
          semanticLabel: '回到房间',
          focusRadius: BorderRadius.circular(AlistenRadii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlistenSpacing.xxs,
              vertical: AlistenSpacing.xxs,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _Progress extends ConsumerWidget {
  const _Progress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (status, position, duration) = ref.watch(
      playbackControllerProvider.select(
        (playback) =>
            (playback.status, playback.positionMs, playback.durationMs),
      ),
    );
    // 手机上这句说明在歌名下面；这里没有那一行，放在进度的位置。
    if (status == LocalPlaybackStatus.unavailable) {
      return Text(
        localPlaybackNote(status)!.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AlistenTypography.secondary.copyWith(
          color: AlistenColors.of(context).danger,
        ),
      );
    }
    return PlaybackProgressBar(positionMs: position, durationMs: duration);
  }
}

class _Volume extends ConsumerWidget {
  const _Volume();

  static const _sliderWidth = 132.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (volume, muted) = ref.watch(
      playbackControllerProvider.select(
        (playback) => (playback.volume, playback.muted),
      ),
    );
    final playback = ref.read(playbackControllerProvider.notifier);
    int level(double value) => (value * 100).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconCircleButton(
          icon: muted ? AlistenIcons.speakerSlash : AlistenIcons.speakerHigh,
          semanticLabel: muted ? '取消静音' : '静音',
          style: IconCircleButtonStyle.plain,
          onPressed: () => unawaited(playback.toggleMute()),
        ),
        SizedBox(
          width: _sliderWidth,
          child: AlistenSlider(
            value: volume / 100,
            semanticLabel: '本机音量',
            onChanged: (value) =>
                unawaited(playback.setVolume(level(value), persist: false)),
            onChangeEnd: (value) =>
                unawaited(playback.setVolume(level(value), persist: true)),
          ),
        ),
      ],
    );
  }
}
