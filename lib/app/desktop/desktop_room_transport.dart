import 'dart:async';

import 'package:alisten/app/desktop/desktop_playback_controls.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_slider.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/playback_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 房间页底部的播放控制：本机暂停、投票切歌和进度居中，左边收藏，右边音量。
class DesktopRoomTransport extends ConsumerWidget {
  const DesktopRoomTransport({super.key});

  static const _controlsWidth = 480.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      roomControllerProvider.select(
        (room) => room.snapshot?.nowPlaying != null,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlistenSpacing.xxl,
        0,
        AlistenSpacing.md,
        AlistenSpacing.md,
      ),
      child: Row(
        children: [
          // 两边一样宽，中间的控制才在正中。
          const SizedBox(width: _Volume.width),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesktopRoomTransport._controlsWidth,
                ),
                child: playing
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DesktopPlaybackControls(gap: AlistenSpacing.md),
                          SizedBox(height: AlistenSpacing.xs),
                          _Progress(),
                        ],
                      )
                    : null,
              ),
            ),
          ),
          const _Volume(),
        ],
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
  static const width = AlistenSizes.iconButton + _sliderWidth;

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
