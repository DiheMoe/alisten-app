import 'dart:async';

import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/pick_controller.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/animated_resize.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/playback_progress_bar.dart'
    show clockText, spokenDuration;
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// [title] 用于在提示和读屏文字里称呼这首歌。
typedef PickSong = void Function(Track track, String title);

const openOriginalHint = '在原平台打开';

const _cannotOpen = '打不开这首歌在原平台的页面';

const _bounceScale = 1.12;

/// [onResult] 必须比页面存活更久。这首歌的请求仍在进行时不再发送，也不报告，
/// 返回 null。
Future<MutationResult<QueueEntry>?> pickSong(
  WidgetRef ref,
  QueueResultCallback onResult,
  Track track,
  String title,
) async {
  final result = await ref.read(pickControllerProvider.notifier).pick(track);
  if (result == null) return null;
  // 链接曲目的标题要等房间收下之后才知道。
  final named = switch (result) {
    MutationSucceeded(:final value) when value.meta.title.isNotEmpty =>
      value.meta.title,
    _ => title,
  };
  onResult(result, named.isEmpty ? '已点歌' : '已点歌《$named》');
  return result;
}

Future<void> openOriginalPage(
  String pageUrl,
  ValueChanged<String> onNotice,
) async {
  final uri = Uri.tryParse(pageUrl);
  var opened = false;
  if (uri != null && (uri.isScheme('https') || uri.isScheme('http'))) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      opened = false;
    }
  }
  if (!opened) onNotice(_cannotOpen);
}

String songSubtitle(TrackMeta meta) {
  return meta.album.isEmpty ? meta.artist : '${meta.artist} · ${meta.album}';
}

// 点过之后点歌状态占据时长的位置，标题在大字号下仍有足够空间。
class SongRow extends ConsumerWidget {
  const SongRow({
    required this.song,
    required this.onPick,
    required this.onOpen,
    super.key,
  });

  final TrackSummary song;
  final PickSong onPick;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = song.meta;
    final picked = ref.watch(
      pickControllerProvider.select((picks) => picks.of(song.track) != null),
    );
    final duration = picked ? 0 : meta.durationMs;
    return TrackRow(
      title: meta.title,
      subtitle: songSubtitle(meta),
      coverUrl: meta.coverUrl,
      onLongPress: meta.pageUrl.isEmpty ? null : () => onOpen(meta.pageUrl),
      longPressHint: openOriginalHint,
      padding: const EdgeInsets.fromLTRB(
        AlistenSpacing.page,
        AlistenSpacing.xxs,
        AlistenSpacing.xs,
        AlistenSpacing.xxs,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (duration > 0)
            Semantics(
              label: spokenDuration(duration),
              child: ExcludeSemantics(
                child: Text(
                  clockText(duration),
                  style: AlistenTypography.timecode.copyWith(
                    color: AlistenColors.of(context).onGlassMuted,
                  ),
                ),
              ),
            ),
          PickControl(track: song.track, title: meta.title, onPick: onPick),
        ],
      ),
    );
  }
}

class OpenOnLongPress extends StatelessWidget {
  const OpenOnLongPress({
    required this.pageUrl,
    required this.onOpen,
    required this.radius,
    required this.child,
    super.key,
  });

  final String pageUrl;
  final ValueChanged<String> onOpen;

  /// 焦点框的圆角半径。
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (pageUrl.isEmpty) return Semantics(container: true, child: child);
    return Pressable(
      onPressed: null,
      onLongPress: () => onOpen(pageUrl),
      longPressHint: openOriginalHint,
      button: false,
      focusRadius: BorderRadius.circular(radius),
      child: child,
    );
  }
}

class PickUnavailableNotice extends ConsumerWidget {
  const PickUnavailableNotice({
    this.padding = const EdgeInsets.fromLTRB(
      AlistenSpacing.page,
      0,
      AlistenSpacing.page,
      AlistenSpacing.xs,
    ),
    super.key,
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (connection, entered) = ref.watch(
      roomControllerProvider.select(
        (room) => (room.status, room.activeRoomId != null),
      ),
    );
    if (connection == RoomConnectionStatus.open) return const SizedBox.shrink();
    final stopped = connection == RoomConnectionStatus.stopped;
    return Padding(
      padding: padding,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: entered
            ? StatusPill(
                label: '连接后可点歌',
                icon: stopped
                    ? AlistenIcons.cloudSlash
                    : AlistenIcons.arrowsClockwise,
                tone: stopped ? StatusTone.danger : StatusTone.warning,
                busy: !stopped,
              )
            : const StatusPill(label: '进入房间后可点歌', icon: AlistenIcons.door),
      ),
    );
  }
}

/// 未点和点歌中时按钮的样子；点过之后按结果着色，与样式无关。
enum PickTone {
  /// 品牌色实底：卡片上突出显示的那一首，或叠在封面上、要实底才看得清的地方。
  filled,

  /// 玻璃底、品牌色图标：一屏有许多行都能点歌时，一列实心圆点太抢眼。
  tonal,

  /// 玻璃底、文字色图标：点歌不是主操作的地方，例如播放历史和歌单。
  quiet,
}

class PickControl extends ConsumerWidget {
  const PickControl({
    required this.track,
    required this.title,
    required this.onPick,
    this.label,
    this.wide = false,
    this.expand = false,
    this.tone = PickTone.tonal,
    this.blockedReason,
    super.key,
  });

  final Track track;
  final String title;
  final PickSong onPick;
  final PickTone tone;

  final String? label;

  /// 在加号旁写上“点歌”，用于卡片上突出显示的那一首歌。
  final bool wide;

  /// 占满可用宽度，只与 [wide] 一起使用。
  final bool expand;

  /// 不为 null 时按钮不可用，读屏名称就是这段文字，例如临时房间里的链接曲目。
  final String? blockedReason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      pickControllerProvider.select((picks) => picks.of(track)),
    );
    final connected = ref.watch(
      roomControllerProvider.select(
        (room) => room.status == RoomConnectionStatus.open,
      ),
    );
    final usable =
        connected && status != PickStatus.sending && status != PickStatus.added;
    final blocked = blockedReason;
    return PickButton(
      status: status,
      label: blocked ?? label ?? '点歌《$title》',
      wide: wide,
      expand: expand,
      tone: tone,
      onPressed: usable && blocked == null ? () => onPick(track, title) : null,
    );
  }
}

// 点歌结果同时用图标和文字表达，不只靠颜色区分。
class PickButton extends StatefulWidget {
  const PickButton({
    required this.status,
    required this.label,
    required this.onPressed,
    this.wide = false,
    this.expand = false,
    this.tone = PickTone.tonal,
    super.key,
  });

  final PickStatus? status;

  /// 例如“点歌《晴天》”；读屏把点歌状态作为值朗读。
  final String label;
  final VoidCallback? onPressed;
  final bool wide;
  final bool expand;
  final PickTone tone;

  @override
  State<PickButton> createState() => _PickButtonState();
}

class _PickButtonState extends State<PickButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: AlistenDurations.bounce,
  );

  late final Animation<double> _scale = _bounce.drive(
    TweenSequence([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: _bounceScale,
        ).chain(CurveTween(curve: AlistenCurves.standard)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: _bounceScale,
          end: 1.0,
        ).chain(CurveTween(curve: AlistenCurves.bounce)),
        weight: 65,
      ),
    ]),
  );

  @override
  void didUpdateWidget(PickButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == PickStatus.added &&
        oldWidget.status != PickStatus.added &&
        !MediaQuery.disableAnimationsOf(context)) {
      unawaited(_bounce.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final status = widget.status;
    final wide = widget.wide;
    final short = AlistenDurations.of(context, AlistenDurations.short);
    final pill = BorderRadius.circular(AlistenRadii.pill);

    final unpicked = status == null || status == PickStatus.sending;
    final tone = unpicked ? widget.tone : null;
    final plain = switch (widget.tone) {
      PickTone.filled => colors.onBrand,
      PickTone.tonal => colors.brand,
      PickTone.quiet => colors.onGlass,
    };
    final (IconData? icon, String? words, Color ink) = switch (status) {
      null => (AlistenIcons.plusBold, wide ? '点歌' : null, plain),
      PickStatus.sending => (null, '点歌中', plain),
      PickStatus.added => (AlistenIcons.checkBold, '已点', colors.success),
      PickStatus.failed => (
        AlistenIcons.exclamationMarkBold,
        '失败',
        colors.danger,
      ),
      PickStatus.unknown => (AlistenIcons.questionBold, '结果未知', colors.warning),
    };
    final value = switch (status) {
      null => null,
      PickStatus.sending => busySemanticValue,
      PickStatus.added || PickStatus.failed || PickStatus.unknown => words,
    };
    final height = wide ? AlistenSizes.iconButton : AlistenSizes.rowAction;
    const iconSize = AlistenSizes.iconSm;

    final content = Row(
      key: ValueKey(status),
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: iconSize,
          child: icon == null
              ? Center(
                  child: BusyIndicator(
                    size: AlistenSizes.inlineIcon,
                    color: ink,
                  ),
                )
              : Icon(icon, size: iconSize, color: ink),
        ),
        if (words != null) ...[
          const SizedBox(width: AlistenSpacing.xxs),
          Flexible(
            child: Text(
              words,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AlistenTypography.weighted(
                wide
                    ? AlistenTypography.bodyStrong
                    : AlistenTypography.secondary,
                FontWeight.w700,
              ).copyWith(color: ink),
            ),
          ),
        ],
      ],
    );

    final face = AnimatedContainer(
      duration: short,
      curve: AlistenCurves.standard,
      constraints: BoxConstraints(minWidth: height, minHeight: height),
      padding: EdgeInsets.symmetric(
        horizontal: words == null
            ? 0
            : wide
            ? AlistenSpacing.lg
            : AlistenSpacing.sm,
      ),
      decoration: BoxDecoration(
        borderRadius: pill,
        color: switch (tone) {
          PickTone.filled => colors.brand,
          PickTone.tonal || PickTone.quiet => colors.glassFill,
          null => ink.withValues(alpha: 0.14),
        },
        border: Border.all(
          color: switch (tone) {
            PickTone.filled => Colors.transparent,
            PickTone.tonal || PickTone.quiet => colors.glassStroke,
            null => ink.withValues(alpha: 0.35),
          },
        ),
      ),
      child: AnimatedResize(
        duration: short,
        curve: AlistenCurves.emphasized,
        child: AnimatedSwitcher(
          duration: short,
          switchInCurve: AlistenCurves.standard,
          switchOutCurve: AlistenCurves.exit,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: animation.drive(Tween(begin: 0.6, end: 1)),
              child: child,
            ),
          ),
          child: content,
        ),
      ),
    );

    return MergeSemantics(
      child: Semantics(
        value: value,
        child: Pressable(
          onPressed: widget.onPressed,
          semanticLabel: widget.label,
          // 点歌中和已点不算不可用，不调暗。
          dimWhenDisabled:
              status != PickStatus.sending && status != PickStatus.added,
          focusRadius: pill,
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AlistenSizes.minTouchTarget,
                minHeight: AlistenSizes.minTouchTarget,
              ),
              child: Center(
                widthFactor: widget.expand ? null : 1,
                child: ScaleTransition(scale: _scale, child: face),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
