import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/playback/application/local_playback_state.dart';
import 'package:alisten/features/playback/application/playback_controller.dart';
import 'package:alisten/features/playback/presentation/local_playback_status.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_slider.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/nudge.dart';
import 'package:alisten/shared/ui/popover.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlayerControls extends ConsumerStatefulWidget {
  const PlayerControls({
    required this.compact,
    required this.onVoteSkip,
    this.vote,
    this.voting = false,
    this.interactive = true,
    super.key,
  });

  final bool compact;
  final VoidCallback? onVoteSkip;
  final VoteSkipResult? vote;
  final bool voting;

  /// 为 false 时不接收触摸，也不被屏幕阅读器读出。
  final bool interactive;

  /// 完整播放器上这一行的高度。
  static double get height => _PlayButton.target(large: true);

  static String? _voteValue(VoteSkipResult? vote) =>
      vote == null ? null : '已投 ${vote.votes}/${vote.requiredVotes}';

  @override
  ConsumerState<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends ConsumerState<PlayerControls> {
  bool _volumeOpen = false;

  @override
  void didUpdateWidget(PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.interactive || widget.compact) _volumeOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(
      playbackControllerProvider.select((playback) => playback.status),
    );
    final playback = ref.read(playbackControllerProvider.notifier);
    void toggle() => unawaited(playback.toggleLocalPause());
    final vote = widget.vote;
    final voteValue = PlayerControls._voteValue(vote);
    // 每次播放只能投一票：计入之后保持不变。
    final onVoteSkip = widget.voting || vote != null ? null : widget.onVoteSkip;
    final Widget controls;
    if (widget.compact) {
      controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PlayButton(status: status, large: false, onPressed: toggle),
          _CompactVote(
            onPressed: onVoteSkip,
            voting: widget.voting,
            vote: vote,
            value: voteValue,
          ),
        ],
      );
    } else {
      // 两侧只放图标，左右对称；名称由屏幕阅读器读出，票数在角标上。
      controls = Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _Volume(
                open: _volumeOpen,
                onToggle: () => setState(() => _volumeOpen = !_volumeOpen),
                onClose: () => setState(() => _volumeOpen = false),
              ),
            ),
          ),
          _PlayButton(status: status, large: true, onPressed: toggle),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _SideControl(
                icon: AlistenIcons.skipForwardFill,
                semanticLabel: '投票切歌',
                semanticValue: voteValue,
                active: vote != null,
                busy: widget.voting,
                nudge: vote,
                badge: vote,
                onPressed: onVoteSkip,
              ),
            ),
          ),
        ],
      );
    }
    return IgnorePointer(
      ignoring: !widget.interactive,
      child: ExcludeSemantics(excluding: !widget.interactive, child: controls),
    );
  }
}

/// 即将发声（加载或等待开播）时显示转动的指示器，以免看起来像无声的播放；
/// 此时按下仍会挂起播放。
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.status,
    required this.large,
    required this.onPressed,
  });

  final LocalPlaybackStatus status;
  final bool large;
  final VoidCallback onPressed;

  static double _diameter({required bool large}) =>
      large ? AlistenSizes.playControl : AlistenSizes.iconButton;

  static double target({required bool large}) =>
      math.max(_diameter(large: large), AlistenSizes.minTouchTarget);

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final offerPlay =
        status == LocalPlaybackStatus.paused ||
        status == LocalPlaybackStatus.error;
    final pending = isPendingPlayback(status);
    final diameter = _diameter(large: large);
    final iconSize = large ? AlistenSizes.playIcon : AlistenSizes.icon;
    final ink = large ? colors.onControl : colors.onGlass;
    final target = _PlayButton.target(large: large);
    final disc = SizedBox.square(
      dimension: target,
      child: Center(
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: large ? colors.control : colors.glassFill,
            border: large ? null : Border.all(color: colors.glassStroke),
          ),
          child: Center(
            child: pending
                ? BusyIndicator(size: iconSize * 0.75, color: ink)
                : Icon(
                    status == LocalPlaybackStatus.unavailable
                        ? localPlaybackNote(status)!.icon
                        : offerPlay
                        ? AlistenIcons.playFill
                        : AlistenIcons.pauseFill,
                    size: iconSize,
                    color: ink,
                  ),
          ),
        ),
      ),
    );
    // 两首之间或本机无法播放时不作为禁用按钮，而由读屏读出原因。
    if (isPlaybackControlInert(status)) {
      return Semantics(
        container: true,
        label: localPlaybackNote(status)!.text,
        child: disc,
      );
    }
    return Pressable(
      onPressed: onPressed,
      semanticLabel: offerPlay ? '恢复本机播放' : '暂停本机播放',
      focusRadius: BorderRadius.circular(target / 2),
      child: Semantics(
        value: pending
            ? localPlaybackNote(status)?.text
            : status == LocalPlaybackStatus.error
            ? '播放失败'
            : null,
        child: disc,
      ),
    );
  }
}

class _Volume extends ConsumerWidget {
  const _Volume({
    required this.open,
    required this.onToggle,
    required this.onClose,
  });

  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final silent = ref.watch(
      playbackControllerProvider.select(
        (playback) => playback.muted || playback.volume == 0,
      ),
    );
    return Popover(
      open: open,
      onClose: onClose,
      offset: const Offset(-AlistenSpacing.xs, -AlistenSpacing.xs),
      padding: const EdgeInsetsDirectional.fromSTEB(
        AlistenSpacing.xxs,
        AlistenSpacing.xxs,
        AlistenSpacing.md,
        AlistenSpacing.xxs,
      ),
      content: const _VolumePanel(),
      child: _SideControl(
        icon: silent ? AlistenIcons.speakerSlash : AlistenIcons.speakerHigh,
        semanticLabel: '调节本机音量',
        expanded: open,
        active: open,
        onPressed: onToggle,
      ),
    );
  }
}

const _volumePanelWidth = 280.0;

class _VolumePanel extends ConsumerWidget {
  const _VolumePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    final (volume, muted) = ref.watch(
      playbackControllerProvider.select(
        (playback) => (playback.volume, playback.muted),
      ),
    );
    final playback = ref.read(playbackControllerProvider.notifier);
    int level(double value) => (value * 100).round();
    return SizedBox(
      width: _volumePanelWidth,
      child: Row(
        children: [
          IconCircleButton(
            icon: muted ? AlistenIcons.speakerSlash : AlistenIcons.speakerHigh,
            semanticLabel: muted ? '取消静音' : '静音',
            style: IconCircleButtonStyle.plain,
            onPressed: () => unawaited(playback.toggleMute()),
          ),
          Expanded(
            child: AlistenSlider(
              value: volume / 100,
              semanticLabel: '本机音量',
              onChanged: (value) =>
                  unawaited(playback.setVolume(level(value), persist: false)),
              onChangeEnd: (value) =>
                  unawaited(playback.setVolume(level(value), persist: true)),
            ),
          ),
          const SizedBox(width: AlistenSpacing.xs),
          ExcludeSemantics(
            child: Text(
              '$volume',
              style: AlistenTypography.timecode.copyWith(
                color: muted ? colors.onGlassMuted : colors.onGlass,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideControl extends StatelessWidget {
  const _SideControl({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.semanticValue,
    this.expanded,
    this.active = false,
    this.busy = false,
    this.nudge,
    this.badge,
  });

  final IconData icon;
  final String semanticLabel;
  final String? semanticValue;
  final VoidCallback? onPressed;

  /// 只有会展开内容的控件才非 null。
  final bool? expanded;

  /// 展开内容打开或操作效果仍在（如投票已计入）时点亮。
  final bool active;
  final bool busy;

  /// 变成新的非空值时，图标向前推一下，表示操作已计入。
  final Object? nudge;

  final VoteSkipResult? badge;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    const disc = AlistenSizes.minTouchTarget;
    final badge = this.badge;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      // 忙碌或投票已计入时不可点按，但并非不可用，不变暗。
      dimWhenDisabled: !busy && !active,
      expanded: expanded,
      focusRadius: BorderRadius.circular(disc / 2),
      child: Semantics(
        value: busy ? busySemanticValue : semanticValue,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: AlistenDurations.of(context, AlistenDurations.short),
              curve: AlistenCurves.standard,
              width: disc,
              height: disc,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? colors.onGlass.withValues(alpha: 0.2)
                    : colors.glassFill,
                border: Border.all(
                  color: active
                      ? colors.onGlass.withValues(alpha: 0.3)
                      : colors.glassStroke,
                ),
              ),
              child: Center(
                child: busy
                    ? const BusyIndicator(size: AlistenSizes.iconSm)
                    : Nudge(
                        trigger: nudge,
                        child: Icon(
                          icon,
                          size: AlistenSizes.icon,
                          color: colors.onGlass,
                        ),
                      ),
              ),
            ),
            if (badge != null)
              PositionedDirectional(
                top: -AlistenSpacing.xxs / 2,
                end: -AlistenSpacing.xxs / 2,
                child: _VoteBadge(vote: badge),
              ),
          ],
        ),
      ),
    );
  }
}

const _badgeMaxScale = 1.4;

class _CompactVote extends StatelessWidget {
  const _CompactVote({
    required this.onPressed,
    required this.voting,
    required this.vote,
    required this.value,
  });

  final VoidCallback? onPressed;
  final bool voting;
  final VoteSkipResult? vote;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final vote = this.vote;
    const disc = AlistenSizes.iconButton;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: '投票切歌',
      dimWhenDisabled: !voting && vote == null,
      focusRadius: BorderRadius.circular(AlistenSizes.minTouchTarget / 2),
      child: Semantics(
        value: voting ? busySemanticValue : value,
        child: SizedBox.square(
          dimension: AlistenSizes.minTouchTarget,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: disc,
                height: disc,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.glassFill,
                  border: Border.all(color: colors.glassStroke),
                ),
                child: Center(
                  child: voting
                      ? const BusyIndicator(size: AlistenSizes.iconSm)
                      : Nudge(
                          trigger: vote,
                          child: Icon(
                            AlistenIcons.skipForwardFill,
                            size: AlistenSizes.icon,
                            color: colors.onGlass,
                          ),
                        ),
                ),
              ),
              if (vote != null)
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: _VoteBadge(vote: vote),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 票数另作为按钮的值读出，角标本身不读。
class _VoteBadge extends StatelessWidget {
  const _VoteBadge({required this.vote});

  final VoteSkipResult vote;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.brand,
          borderRadius: BorderRadius.circular(AlistenRadii.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.xxs),
          child: Text(
            '${vote.votes}/${vote.requiredVotes}',
            // 徽标附着在固定尺寸的按钮上，所以限制缩放。
            textScaler: MediaQuery.textScalerOf(context)
                .clamp(maxScaleFactor: _badgeMaxScale),
            style: AlistenTypography.timecode.copyWith(
              fontSize: AlistenTypography.caption.fontSize,
              color: colors.onBrand,
            ),
          ),
        ),
      ),
    );
  }
}
