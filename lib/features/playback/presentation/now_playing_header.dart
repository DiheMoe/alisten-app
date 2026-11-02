import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playback/playback_identity.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/playback/application/local_playback_state.dart';
import 'package:alisten/features/playback/application/playback_controller.dart';
import 'package:alisten/features/playback/presentation/local_playback_status.dart';
import 'package:alisten/features/playback/presentation/player_controls.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/playback_progress_bar.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [compact] 时曲目收拢为顶部一行，[body] 显示在其下方；否则是占满空间的
/// 播放器。
class NowPlayingHeader extends ConsumerStatefulWidget {
  const NowPlayingHeader({
    required this.nowPlaying,
    required this.compact,
    required this.connected,
    required this.onAddSong,
    required this.onVoteSkipped,
    this.onExpand,
    this.body,
    super.key,
  });

  final NowPlaying? nowPlaying;
  final bool compact;
  final bool connected;
  final VoidCallback onAddSong;
  final ValueChanged<MutationResult<VoteSkipResult>> onVoteSkipped;
  final VoidCallback? onExpand;
  final Widget? body;

  @override
  ConsumerState<NowPlayingHeader> createState() => _NowPlayingHeaderState();
}

class _NowPlayingHeaderState extends ConsumerState<NowPlayingHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _layout = AnimationController(
    vsync: this,
    value: widget.compact ? 1 : 0,
  )..addStatusListener((_) => setState(() {}));
  // emphasized 先急后缓；返回播放器时翻转使用，避免封面先停顿再放大。
  late final CurvedAnimation _shrink = CurvedAnimation(
    parent: _layout,
    curve: AlistenCurves.emphasized,
    reverseCurve: AlistenCurves.emphasized.flipped,
  );
  // 播放器部件在移动开始时即淡出，紧凑行的其他部件等封面和标题到位后才出现，
  // 避免移动途中压住标题。
  late final CurvedAnimation _playerLeaving = CurvedAnimation(
    parent: _shrink,
    curve: const Interval(0, 0.45),
  );
  late final Animation<double> _playerOpacity = ReverseAnimation(
    _playerLeaving,
  );
  late final CurvedAnimation _rowOpacity = CurvedAnimation(
    parent: _shrink,
    curve: const Interval(0.9, 1),
  );

  (PlaybackIdentity, VoteSkipResult)? _vote;
  PlaybackIdentity? _voting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _layout.duration = AlistenDurations.of(context, AlistenDurations.layout);
  }

  @override
  void didUpdateWidget(NowPlayingHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.compact == oldWidget.compact) return;
    unawaited(widget.compact ? _layout.forward() : _layout.reverse());
  }

  @override
  void dispose() {
    _rowOpacity.dispose();
    _playerLeaving.dispose();
    _shrink.dispose();
    _layout.dispose();
    super.dispose();
  }

  Future<void> _voteSkip(PlaybackIdentity playback) async {
    // 先取出回调：页面关闭后也要报告结果。
    final report = widget.onVoteSkipped;
    final actions = ref.read(queueActionsProvider);
    setState(() => _voting = playback);
    final result = await actions.voteSkip();
    report(result);
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
    final nowPlaying = widget.nowPlaying;
    final playback = nowPlaying == null
        ? null
        : PlaybackIdentity(
            entryId: nowPlaying.entry.id,
            startedAtMs: nowPlaying.startedAtMs,
          );
    final vote = switch (_vote) {
      (final votedOn, final result) when votedOn == playback => result,
      _ => null,
    };
    final voting = playback != null && _voting == playback;
    final onVoteSkip = playback != null && widget.connected
        ? () => unawaited(_voteSkip(playback))
        : null;
    final compact = widget.compact;
    final status = _layout.status;
    final body = widget.body;
    // 在 LayoutBuilder 之外测量，因为键盘升降时它每帧都会重建。
    final scaler = MediaQuery.textScalerOf(context);
    final playerTitleHeight = _TitleBlock.heightOf(scaler, compact: false);
    final rowTitleHeight = _TitleBlock.heightOf(scaler, compact: true);
    final sideLabels = PlayerSideLabels.measure(
      scaler: scaler,
      direction: Directionality.of(context),
      vote: vote,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = _PlayerFit.of(
          context,
          constraints.biggest,
          titleHeight: playerTitleHeight,
          labels: sideLabels,
        );
        return CustomMultiChildLayout(
          delegate: _StageLayout(
            shrink: _shrink,
            fit: fit,
            playerTitleHeight: playerTitleHeight,
            rowTitleHeight: rowTitleHeight,
          ),
          children: [
            if (body != null && !status.isDismissed)
              LayoutId(
                id: _Part.body,
                child: FadeTransition(
                  opacity: _shrink,
                  child: _Interactive(
                    enabled: compact,
                    child: ExcludeFocus(excluding: !compact, child: body),
                  ),
                ),
              ),
            LayoutId(
              id: _Part.cover,
              child: _Cover(
                nowPlaying: nowPlaying,
                shrink: _shrink,
                compact: compact,
                onTap: compact ? widget.onExpand : null,
              ),
            ),
            LayoutId(
              id: _Part.title,
              child: _TitleBlock(nowPlaying: nowPlaying, shrink: _shrink),
            ),
            if (!status.isCompleted)
              LayoutId(
                id: _Part.player,
                child: FadeTransition(
                  opacity: _playerOpacity,
                  child: _Interactive(
                    enabled: !compact,
                    child: nowPlaying == null
                        ? Center(
                            child: PillButton(
                              label: '点歌',
                              icon: Icons.add_rounded,
                              large: true,
                              glow: true,
                              onPressed: widget.onAddSong,
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 进度频繁重绘，隔开以免连带重绘封面光晕。
                              RepaintBoundary(
                                child: _Progress(nowPlaying: nowPlaying),
                              ),
                              SizedBox(height: fit.progressToControls),
                              PlayerControls(
                                compact: false,
                                interactive: !compact,
                                labelled: fit.labelled,
                                labels: sideLabels,
                                vote: vote,
                                voting: voting,
                                onVoteSkip: onVoteSkip,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            if (nowPlaying != null && !status.isDismissed) ...[
              LayoutId(
                id: _Part.rowControls,
                child: FadeTransition(
                  opacity: _rowOpacity,
                  child: PlayerControls(
                    compact: true,
                    interactive: compact,
                    vote: vote,
                    voting: voting,
                    onVoteSkip: onVoteSkip,
                  ),
                ),
              ),
              LayoutId(
                id: _Part.rowProgress,
                child: FadeTransition(
                  opacity: _rowOpacity,
                  child: RepaintBoundary(
                    child: _ThinProgress(nowPlaying: nowPlaying),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Interactive extends StatelessWidget {
  const _Interactive({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: ExcludeSemantics(excluding: !enabled, child: child),
    );
  }
}

/// 没有播放时封面的 Hero 标签。播放中的封面用条目的标签，才能与迷你播放器
/// 互相飞入飞出。
const _silentCoverTag = Object();

class _Cover extends ConsumerWidget {
  const _Cover({
    required this.nowPlaying,
    required this.shrink,
    required this.compact,
    required this.onTap,
  });

  final NowPlaying? nowPlaying;
  final Animation<double> shrink;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    final held = ref.watch(
      playbackControllerProvider.select(
        (playback) =>
            playback.status == LocalPlaybackStatus.paused ||
            playback.status == LocalPlaybackStatus.error ||
            playback.status == LocalPlaybackStatus.unavailable,
      ),
    );
    final nowPlaying = this.nowPlaying;
    final url = nowPlaying?.entry.meta.coverUrl;
    final full = colors.glowShadow.first;
    final faint = full
        .scale(0.3)
        .copyWith(color: full.color.withValues(alpha: full.color.a * 0.35));
    // 动画途经各种尺寸，只按播放器封面的大致尺寸解码一次。
    final decodeSize = math.min(MediaQuery.sizeOf(context).width, _maxCover);
    final trackDuration = AlistenDurations.of(context, AlistenDurations.track);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return ExcludeSemantics(
          excluding: onTap == null,
          child: Pressable(
            onPressed: onTap,
            semanticLabel: '返回播放器',
            dimWhenDisabled: false,
            focusRadius: BorderRadius.circular(AlistenRadii.sm),
            child: AnimatedScale(
              scale: held && !compact ? _heldScale : 1,
              duration: AlistenDurations.of(context, AlistenDurations.layout),
              curve: AlistenCurves.bounce,
              child: Hero(
                tag: nowPlaying == null
                    ? _silentCoverTag
                    : 'cover-${nowPlaying.entry.id}',
                child: AnimatedBuilder(
                  animation: shrink,
                  builder: (context, child) {
                    final t = shrink.value;
                    final radius = lerpDouble(
                      AlistenRadii.lg,
                      AlistenRadii.sm,
                      t,
                    )!;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow: [BoxShadow.lerp(full, faint, t)!],
                      ),
                      child: AnimatedSwitcher(
                        duration: trackDuration,
                        switchInCurve: AlistenCurves.standard,
                        switchOutCurve: AlistenCurves.exit,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween(
                              begin: _arrivingScale,
                              end: 1.0,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: CoverArt(
                          key: ValueKey(_playKey(nowPlaying)),
                          url: url,
                          size: side,
                          decodeSize: decodeSize,
                          radius: radius,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

const _heldScale = 0.92;
const _arrivingScale = 0.94;
const _maxCover = 440.0;
const _rowCover = 64.0;

/// 同一条目再次播放时也要重新淡入。
String _playKey(NowPlaying? nowPlaying) => nowPlaying == null
    ? ''
    : '${nowPlaying.entry.id}@${nowPlaying.startedAtMs}';

class _TitleBlock extends ConsumerWidget {
  const _TitleBlock({required this.nowPlaying, required this.shrink});

  final NowPlaying? nowPlaying;
  final Animation<double> shrink;

  static TextStyle _title({required bool compact}) =>
      AlistenTypography.weighted(
        compact ? AlistenTypography.bodyStrong : AlistenTypography.title,
        FontWeight.w700,
      );

  static TextStyle _subtitle({required bool compact}) =>
      compact ? AlistenTypography.secondary : AlistenTypography.body;

  static double _gap({required bool compact}) =>
      compact ? AlistenSpacing.xxs / 2 : AlistenSpacing.xxs;

  /// 标题和副标题各占一行时的高度。
  static double heightOf(TextScaler scaler, {required bool compact}) {
    return AlistenTypography.lineHeight(_title(compact: compact), scaler) +
        _gap(compact: compact) +
        AlistenTypography.lineHeight(_subtitle(compact: compact), scaler);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    final nowPlaying = this.nowPlaying;
    final entry = nowPlaying?.entry;
    final status = ref.watch(
      playbackControllerProvider.select((playback) => playback.status),
    );
    final note = entry == null ? null : localPlaybackNote(status);
    final retry = note != null && note.failed
        ? () => unawaited(
            ref.read(playbackControllerProvider.notifier).toggleLocalPause(),
          )
        : null;
    final title = entry?.meta.title ?? '还没有歌，点一首吧';
    final requester = entry == null
        ? null
        : entry.auto
        ? '自动推荐'
        : switch (entry.requestedBy) {
            final member? => '${member.name} 点歌',
            null => null,
          };
    final subtitle = entry == null
        ? '点的歌会在房间里同步播放'
        : [
            entry.meta.artist,
            ?requester,
          ].where((part) => part.isNotEmpty).join(' · ');
    final trackDuration = AlistenDurations.of(context, AlistenDurations.track);
    return AnimatedBuilder(
      animation: shrink,
      builder: (context, _) {
        final t = shrink.value;
        final titleStyle = TextStyle.lerp(
          _title(compact: false),
          _title(compact: true),
          t,
        )!.copyWith(color: colors.onGlass);
        final subtitleStyle = TextStyle.lerp(
          _subtitle(compact: false),
          _subtitle(compact: true),
          t,
        )!.copyWith(color: colors.onGlassMuted);
        return AnimatedSwitcher(
          duration: trackDuration,
          switchInCurve: AlistenCurves.standard,
          switchOutCurve: AlistenCurves.exit,
          transitionBuilder: _fadeLeavingInert,
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.topStart,
            children: [...previous, ?current],
          ),
          child: Column(
            key: ValueKey(_playKey(nowPlaying)),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
              SizedBox(
                height: lerpDouble(
                  _gap(compact: false),
                  _gap(compact: true),
                  t,
                ),
              ),
              AnimatedSwitcher(
                duration: AlistenDurations.of(context, AlistenDurations.short),
                transitionBuilder: _fadeLeavingInert,
                layoutBuilder: (current, previous) => Stack(
                  alignment: AlignmentDirectional.topStart,
                  children: [...previous, ?current],
                ),
                child: note == null
                    ? Text(
                        subtitle,
                        key: const ValueKey('track'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      )
                    : _NoteLine(
                        key: ValueKey(note.text),
                        note: note,
                        style: subtitleStyle,
                        onRetry: retry,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 淡出途中不接收触摸也不被读出，以免已消失的说明（如失败提示）仍可操作。
Widget _fadeLeavingInert(Widget child, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final leaving = !animation.status.isForwardOrCompleted;
      return IgnorePointer(
        ignoring: leaving,
        child: ExcludeSemantics(excluding: leaving, child: child),
      );
    },
    child: FadeTransition(opacity: animation, child: child),
  );
}

class _NoteLine extends StatelessWidget {
  const _NoteLine({
    required this.note,
    required this.style,
    required this.onRetry,
    super.key,
  });

  final LocalPlaybackNote note;
  final TextStyle style;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final ink = note.failed ? colors.danger : colors.onGlassMuted;
    // 图标与文字等高，这一行才能保持副标题的高度。
    final size = MediaQuery.textScalerOf(context).scale(style.fontSize!);
    final line = Row(
      children: [
        if (note.busy)
          BusyIndicator(size: size, color: ink)
        else
          Icon(note.icon, size: size, color: ink),
        const SizedBox(width: AlistenSpacing.xxs),
        Flexible(
          child: Text(
            note.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(color: ink),
          ),
        ),
      ],
    );
    final onRetry = this.onRetry;
    if (onRetry == null) {
      return Semantics(container: true, liveRegion: true, child: line);
    }
    return Pressable(
      onPressed: onRetry,
      child: Semantics(liveRegion: true, child: line),
    );
  }
}

int _lengthOf(NowPlaying nowPlaying, int localMs) =>
    nowPlaying.durationMs > 0 ? nowPlaying.durationMs : localMs;

class _Progress extends ConsumerWidget {
  const _Progress({required this.nowPlaying});

  final NowPlaying nowPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (position, length) = ref.watch(
      playbackControllerProvider.select(
        (playback) => (playback.positionMs, playback.durationMs),
      ),
    );
    return PlaybackProgressBar(
      positionMs: position,
      durationMs: _lengthOf(nowPlaying, length),
    );
  }
}

/// 只显示不读出，读出时间的是播放器的进度条。
class _ThinProgress extends ConsumerWidget {
  const _ThinProgress({required this.nowPlaying});

  final NowPlaying nowPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    final (position, length) = ref.watch(
      playbackControllerProvider.select(
        (playback) => (playback.positionMs, playback.durationMs),
      ),
    );
    final duration = _lengthOf(nowPlaying, length);
    final played = duration <= 0 ? 0.0 : (position / duration).clamp(0.0, 1.0);
    final shape = BorderRadius.circular(AlistenRadii.pill);
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.outline, borderRadius: shape),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: played,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.onGlass,
                borderRadius: shape,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Part { body, cover, title, player, rowControls, rowProgress }

const _coverToTitle = AlistenSpacing.xl;
const _titleToControls = AlistenSpacing.lg;

/// 封面占满高度时播放器上下的留白。
const _breathing = AlistenSpacing.md;

/// 播放器在剩余高度中的纵向位置，略高于正中。
const _playerBias = 0.42;

/// 播放器控件淡出时下沉、body 淡入时上升的距离。
const _drift = AlistenSpacing.xxxl;

/// 竖排时封面小于此尺寸就隐藏，把高度让给标题和控件。
const _minCover = AlistenSizes.featureCover;

const _sideGap = AlistenSpacing.xl;

/// 并排时标题和控件一栏的最小宽度，封面只用剩余宽度。
const _sideMinColumn =
    AlistenSizes.playControl +
    2 * (AlistenSizes.minTouchTarget + AlistenSpacing.xl);

/// 宽大于高时封面与标题、控件并排；高度不够时先去掉两侧控件的文字，再收紧
/// 间距。
@immutable
final class _PlayerFit {
  const _PlayerFit({
    required this.sideBySide,
    required this.labelled,
    required this.tight,
  });

  /// 选出放得下的最完整的一档；都放不下时用最紧凑的一档，由布局把控件保持在
  /// 可见范围内。
  factory _PlayerFit.of(
    BuildContext context,
    Size size, {
    required double titleHeight,
    required PlayerSideLabels labels,
  }) {
    final sideBySide = size.width > size.height;
    final progress = PlaybackProgressBar.heightOf(context);
    final steps = [
      for (final (labelled, tight) in const [
        (true, false),
        (false, false),
        (false, true),
      ])
        _PlayerFit(sideBySide: sideBySide, labelled: labelled, tight: tight),
    ];
    _Arrangement arrange(_PlayerFit fit) => _arrange(
      size,
      fit,
      titleHeight: titleHeight,
      controlsHeightAt: (column) =>
          progress +
          fit.progressToControls +
          PlayerControls.heightOf(
            width: column,
            labelled: fit.labelled,
            labels: labels,
          ),
    );
    // 竖排时先找能保留封面的一档，找不到再接受隐藏封面。
    for (final keepCover in sideBySide ? const [false] : const [true, false]) {
      for (final fit in steps) {
        final arranged = arrange(fit);
        if (arranged.spare >= 0 && (!keepCover || !arranged.cover.isEmpty)) {
          return fit;
        }
      }
    }
    return steps.last;
  }

  final bool sideBySide;
  final bool labelled;
  final bool tight;

  double get breathing => tight ? 0 : _breathing;
  double get titleToControls => tight ? AlistenSpacing.sm : _titleToControls;
  double get progressToControls =>
      tight ? AlistenSpacing.xs : AlistenSpacing.md;

  @override
  bool operator ==(Object other) =>
      other is _PlayerFit &&
      other.sideBySide == sideBySide &&
      other.labelled == labelled &&
      other.tight == tight;

  @override
  int get hashCode => Object.hash(sideBySide, labelled, tight);
}

/// [spare] 是按 [_PlayerFit] 留出上下空白后余下的高度，小于 0 表示放不下。
typedef _Arrangement = ({
  Rect cover,
  double columnStart,
  double column,
  double titleTop,
  double controlsTop,
  double spare,
});

/// 选档（估算高度）和布局（实际排版高度）共用同一套算术。[controlsHeightAt]
/// 每次排列只调用一次。
///
/// 放不下时控件上移，始终留在 [size] 内可以点按；标题宁可被控件压住，也不移到
/// 区域上方压住顶栏。
_Arrangement _arrange(
  Size size,
  _PlayerFit fit, {
  required double titleHeight,
  required double Function(double column) controlsHeightAt,
}) {
  final Size(:width, :height) = size;
  final Rect cover;
  final double column;
  final double columnStart;
  final double textTop;
  final double controls;
  final double spare;
  if (fit.sideBySide) {
    final room = math.max(0.0, width - 2 * AlistenSpacing.page - _sideGap);
    final side = math.max(
      0.0,
      [
        height - 2 * fit.breathing,
        _maxCover,
        room - _sideMinColumn,
      ].reduce(math.min),
    );
    column = math.min(_maxCover, room - side);
    final start = (width - side - _sideGap - column) / 2;
    columnStart = start + side + _sideGap;
    controls = controlsHeightAt(column);
    final text = titleHeight + fit.titleToControls + controls;
    cover = Rect.fromLTWH(start, (height - side) / 2, side, side);
    textTop = (height - text) / 2;
    spare = height - 2 * fit.breathing - text;
  } else {
    column = math.min(math.max(0.0, width - 2 * AlistenSpacing.xl), _maxCover);
    columnStart = (width - column) / 2;
    controls = controlsHeightAt(column);
    final text = titleHeight + fit.titleToControls + controls;
    var side = (height - text - _coverToTitle - 2 * fit.breathing).clamp(
      0.0,
      column,
    );
    if (side < _minCover) side = 0;
    final gap = side == 0 ? 0.0 : _coverToTitle;
    final top = math.max(0.0, (height - side - gap - text) * _playerBias);
    cover = Rect.fromLTWH((width - side) / 2, top, side, side);
    textTop = cover.bottom + gap;
    spare = height - 2 * fit.breathing - side - gap - text;
  }
  final controlsTop = textTop + titleHeight + fit.titleToControls;
  final lift = math.max(0.0, controlsTop + controls - height);
  return (
    cover: cover,
    columnStart: columnStart,
    column: column,
    titleTop: math.max(0.0, textTop - lift),
    controlsTop: controlsTop - lift,
    spare: spare,
  );
}

/// 标题高度按字号计算，播放器往返移动时布局保持一致。
class _StageLayout extends MultiChildLayoutDelegate {
  _StageLayout({
    required this.shrink,
    required this.fit,
    required this.playerTitleHeight,
    required this.rowTitleHeight,
  }) : super(relayout: shrink);

  final Animation<double> shrink;
  final _PlayerFit fit;
  final double playerTitleHeight;
  final double rowTitleHeight;

  double _layoutControls(double width) => hasChild(_Part.player)
      ? layoutChild(
          _Part.player,
          BoxConstraints(minWidth: width, maxWidth: width),
        ).height
      : 0.0;

  @override
  void performLayout(Size size) {
    final t = shrink.value;
    final width = size.width;
    final player = _arrange(
      size,
      fit,
      titleHeight: playerTitleHeight,
      controlsHeightAt: _layoutControls,
    );

    final rowControls = hasChild(_Part.rowControls)
        ? layoutChild(_Part.rowControls, BoxConstraints(maxWidth: width))
        : Size.zero;
    final rowHeight = [
      _rowCover,
      rowTitleHeight,
      rowControls.height,
    ].reduce(math.max);
    const rowTop = AlistenSpacing.xs;
    final rowCoverRect = Rect.fromLTWH(
      AlistenSpacing.page,
      rowTop + (rowHeight - _rowCover) / 2,
      _rowCover,
      _rowCover,
    );
    final rowControlsStart = width - AlistenSpacing.sm - rowControls.width;
    final rowTitleStart = rowCoverRect.right + AlistenSpacing.sm;
    final rowTitleEnd = rowControls == Size.zero
        ? width - AlistenSpacing.page
        : rowControlsStart - AlistenSpacing.xxs;
    final rowProgressTop = rowTop + rowHeight + AlistenSpacing.sm;
    final bodyTop =
        rowProgressTop + AlistenSizes.progressTrack + AlistenSpacing.xs;

    final cover = Rect.lerp(player.cover, rowCoverRect, t)!;
    layoutChild(_Part.cover, BoxConstraints.tight(cover.size));
    positionChild(_Part.cover, cover.topLeft);

    final titleWidth = math.max(
      0.0,
      lerpDouble(player.column, rowTitleEnd - rowTitleStart, t)!,
    );
    layoutChild(
      _Part.title,
      BoxConstraints(minWidth: titleWidth, maxWidth: titleWidth),
    );
    positionChild(
      _Part.title,
      Offset(
        lerpDouble(player.columnStart, rowTitleStart, t)!,
        lerpDouble(
          player.titleTop,
          rowTop + (rowHeight - rowTitleHeight) / 2,
          t,
        )!,
      ),
    );

    if (hasChild(_Part.player)) {
      positionChild(
        _Part.player,
        Offset(player.columnStart, player.controlsTop + t * _drift),
      );
    }
    if (hasChild(_Part.rowControls)) {
      positionChild(
        _Part.rowControls,
        Offset(rowControlsStart, rowTop + (rowHeight - rowControls.height) / 2),
      );
    }
    if (hasChild(_Part.rowProgress)) {
      layoutChild(
        _Part.rowProgress,
        BoxConstraints.tightFor(
          width: width - 2 * AlistenSpacing.page,
          height: AlistenSizes.progressTrack,
        ),
      );
      positionChild(
        _Part.rowProgress,
        Offset(AlistenSpacing.page, rowProgressTop),
      );
    }
    if (hasChild(_Part.body)) {
      layoutChild(
        _Part.body,
        BoxConstraints.tight(Size(width, math.max(0.0, size.height - bodyTop))),
      );
      positionChild(_Part.body, Offset(0, bodyTop + (1 - t) * _drift));
    }
  }

  @override
  bool shouldRelayout(_StageLayout oldDelegate) {
    return oldDelegate.shrink != shrink ||
        oldDelegate.fit != fit ||
        oldDelegate.playerTitleHeight != playerTitleHeight ||
        oldDelegate.rowTitleHeight != rowTitleHeight;
  }
}
