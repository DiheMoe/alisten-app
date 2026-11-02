import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/playback/application/local_playback_state.dart';
import 'package:alisten/features/playback/application/playback_controller.dart';
import 'package:alisten/features/playback/presentation/local_playback_status.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_slider.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
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
    this.labelled = true,
    this.labels,
    super.key,
  }) : assert(compact || labels != null, '播放器的控件需要两侧文字的尺寸');

  final bool compact;
  final VoidCallback? onVoteSkip;
  final VoteSkipResult? vote;
  final bool voting;

  /// 为 false 时不接收触摸，也不被屏幕阅读器读出。
  final bool interactive;

  /// 两侧控件下方是否显示文字；宽度不足以完整显示时也不显示。屏幕阅读器始终
  /// 读出控件名称。
  final bool labelled;

  /// 与 [vote] 对应的文字尺寸。
  final PlayerSideLabels? labels;

  static double heightOf({
    required double width,
    required bool labelled,
    required PlayerSideLabels labels,
  }) {
    final shown = _showsLabels(width, labelled: labelled, labels: labels);
    final side =
        _SideControl.inset +
        AlistenSizes.minTouchTarget +
        (shown ? AlistenSpacing.xs + labels.height : 0);
    return math.max(_PlayButton.target(large: true), side);
  }

  static const _volumeLabel = '音量';

  static String? _voteValue(VoteSkipResult? vote) =>
      vote == null ? null : '已投 ${vote.votes}/${vote.requiredVotes}';

  static String _voteText(VoteSkipResult? vote) => _voteValue(vote) ?? '投票切歌';

  // 两侧的文字要么都完整显示，要么都不显示，不出现被截断的半句。
  static bool _showsLabels(
    double width, {
    required bool labelled,
    required PlayerSideLabels labels,
  }) {
    final side = (width - _PlayButton.target(large: true)) / 2;
    return labelled && labels.width <= side;
  }

  @override
  ConsumerState<PlayerControls> createState() => _PlayerControlsState();
}

/// 字号和文字不变时只量一次，键盘升降使布局每帧重建时无须重新排版。
final class PlayerSideLabels {
  const PlayerSideLabels._({required this.width, required this.height});

  factory PlayerSideLabels.measure({
    required TextScaler scaler,
    required TextDirection direction,
    required VoteSkipResult? vote,
  }) {
    final painter = TextPainter(
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    );
    var width = 0.0;
    for (final label in [
      PlayerControls._volumeLabel,
      PlayerControls._voteText(vote),
    ]) {
      painter
        ..text = TextSpan(text: label, style: _SideControl._labelStyle)
        ..layout();
      width = math.max(width, painter.width);
    }
    painter.dispose();
    final style = _SideControl._labelStyle;
    // 文字只占一行，按字号算出的高度与实际排版一致。
    return PlayerSideLabels._(
      width: width,
      height: scaler.scale(style.fontSize!) * style.height!,
    );
  }

  /// 两段文字中较宽者的宽度。
  final double width;
  final double height;
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
      final voteLabel = PlayerControls._voteText(vote);
      final labels = widget.labels!;
      controls = LayoutBuilder(
        builder: (context, constraints) {
          final labelHeight =
              PlayerControls._showsLabels(
                constraints.maxWidth,
                labelled: widget.labelled,
                labels: labels,
              )
              ? labels.height
              : null;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  heightFactor: 1,
                  child: _Volume(
                    open: _volumeOpen,
                    label: PlayerControls._volumeLabel,
                    labelHeight: labelHeight,
                    onToggle: () => setState(() => _volumeOpen = !_volumeOpen),
                    onClose: () => setState(() => _volumeOpen = false),
                  ),
                ),
              ),
              _PlayButton(status: status, large: true, onPressed: toggle),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.topEnd,
                  heightFactor: 1,
                  child: _SideControl(
                    icon: Icons.skip_next_rounded,
                    label: voteLabel,
                    semanticLabel: '投票切歌',
                    semanticValue: voteValue,
                    labelHeight: labelHeight,
                    active: vote != null,
                    busy: widget.voting,
                    onPressed: onVoteSkip,
                  ),
                ),
              ),
            ],
          );
        },
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
    final ink = large ? Theme.of(context).colorScheme.surface : colors.onGlass;
    final target = _PlayButton.target(large: large);
    final disc = SizedBox.square(
      dimension: target,
      child: Center(
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: large ? colors.onGlass : colors.glassFill,
            border: large ? null : Border.all(color: colors.glassStroke),
            boxShadow: large
                ? [
                    BoxShadow(
                      color: colors.glow.withValues(alpha: 0.35),
                      blurRadius: diameter / 2,
                      offset: Offset(0, diameter / 10),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: pending
                ? BusyIndicator(size: iconSize * 0.75, color: ink)
                : Icon(
                    status == LocalPlaybackStatus.unavailable
                        ? localPlaybackNote(status)!.icon
                        : offerPlay
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
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
    required this.label,
    required this.labelHeight,
    required this.onToggle,
    required this.onClose,
  });

  final bool open;
  final String label;
  final double? labelHeight;
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
        icon: silent ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        label: label,
        semanticLabel: '调节本机音量',
        labelHeight: labelHeight,
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
            icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
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
    required this.label,
    required this.semanticLabel,
    required this.labelHeight,
    required this.onPressed,
    this.semanticValue,
    this.expanded,
    this.active = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final String? semanticValue;

  /// 为 null 时不在圆形按钮下方显示 [label]。
  final double? labelHeight;
  final VoidCallback? onPressed;

  /// 只有会展开内容的控件才非 null。
  final bool? expanded;

  /// 展开内容打开或操作效果仍在（如投票已计入）时点亮。
  final bool active;
  final bool busy;

  /// 使圆形按钮与播放按钮中心对齐的上方留白。
  static const inset =
      (AlistenSizes.playControl - AlistenSizes.minTouchTarget) / 2;

  static final _labelStyle = AlistenTypography.weighted(
    AlistenTypography.secondary,
    FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    const disc = AlistenSizes.minTouchTarget;
    final labelHeight = this.labelHeight;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      // 忙碌或投票已计入时不可点按，但并非不可用，不变暗。
      dimWhenDisabled: !busy && !active,
      expanded: expanded,
      focusRadius: BorderRadius.circular(AlistenRadii.sm),
      child: Semantics(
        value: busy ? busySemanticValue : semanticValue,
        child: Padding(
          padding: const EdgeInsets.only(top: inset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                      : Icon(
                          icon,
                          size: AlistenSizes.icon,
                          color: colors.onGlass,
                        ),
                ),
              ),
              if (labelHeight != null) ...[
                const SizedBox(height: AlistenSpacing.xs),
                SizedBox(
                  height: labelHeight,
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      softWrap: false,
                      style: _labelStyle.copyWith(
                        color: active ? colors.onGlass : colors.onGlassMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
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
                      : Icon(
                          Icons.skip_next_rounded,
                          size: AlistenSizes.icon,
                          color: colors.onGlass,
                        ),
                ),
              ),
              if (vote != null)
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: colors.brandGradient,
                        borderRadius: BorderRadius.circular(AlistenRadii.pill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AlistenSpacing.xxs,
                        ),
                        child: Text(
                          '${vote.votes}/${vote.requiredVotes}',
                          // 徽标附着在固定尺寸的按钮上，所以限制缩放；票数
                          // 另作为按钮的值读出。
                          textScaler: MediaQuery.textScalerOf(context)
                              .clamp(maxScaleFactor: _badgeMaxScale),
                          style: AlistenTypography.timecode.copyWith(
                            fontSize: AlistenTypography.caption.fontSize,
                            color: colors.onBrand,
                          ),
                        ),
                      ),
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
