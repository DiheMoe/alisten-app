import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/app/app_theme.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/playback_progress_bar.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 活动房间的页面下方也保留迷你播放器（被页面遮住），封面才能在两者之间
/// 飞行过渡；其他房间的页面下方不显示它，避免正在进入的房间露出活动房间的内容。
class MiniPlayerHost extends ConsumerWidget {
  const MiniPlayerHost({
    required this.location,
    required this.child,
    super.key,
  });

  final Uri location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomId = ref.watch(
      roomControllerProvider.select((room) => room.activeRoomId),
    );
    final segments = location.pathSegments;
    final routeRoom = segments.length >= 2 && segments.first == 'r'
        ? segments[1]
        : null;
    final media = MediaQuery.of(context);
    final shown =
        roomId != null &&
        media.viewInsets.bottom == 0 &&
        (routeRoom == null ||
            ref.read(roomControllerProvider.notifier).names(routeRoom));
    final bottom = media.padding.bottom + AlistenSpacing.sm;
    final reserved = shown
        ? MiniPlayer.heightOf(context) + AlistenSpacing.sm + AlistenSpacing.xs
        : 0.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(
              bottom: media.padding.bottom + reserved,
            ),
            viewPadding: media.viewPadding.copyWith(
              bottom: media.viewPadding.bottom + reserved,
            ),
          ),
          child: child,
        ),
        Positioned(
          left: AlistenSpacing.sm,
          right: AlistenSpacing.sm,
          bottom: bottom,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AlistenSizes.sheetMaxWidth,
              ),
              child: _MiniPlayerSlot(roomId: shown ? roomId : null),
            ),
          ),
        ),
      ],
    );
  }
}

// 由这里读取房间再传给 [MiniPlayer]：淡出中的迷你播放器仍在组件树中，
// 若自行读取，房间清空后它会变样；传入最后显示的内容才能原样淡出。
class _MiniPlayerSlot extends ConsumerWidget {
  const _MiniPlayerSlot({required this.roomId});

  final String? roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (status, failure, errorMessage, roomName, nowPlaying) = ref.watch(
      roomControllerProvider.select(
        (room) => (
          room.status,
          room.failure,
          room.errorMessage,
          room.snapshot?.room.name ?? room.roomName,
          room.snapshot?.nowPlaying,
        ),
      ),
    );
    final roomId = this.roomId;
    return AnimatedSwitcher(
      duration: AlistenDurations.of(context, AlistenDurations.medium),
      switchInCurve: AlistenCurves.standard,
      switchOutCurve: AlistenCurves.exit,
      transitionBuilder: (child, animation) => AnimatedBuilder(
        animation: animation,
        // 淡出中的迷你播放器与新的那个共用封面的 hero 标签，
        // 点击它还会打开已不存在的房间。
        builder: (context, child) {
          final staying = animation.status.isForwardOrCompleted;
          return IgnorePointer(
            ignoring: !staying,
            child: HeroMode(enabled: staying, child: child!),
          );
        },
        child: FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.4),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
      ),
      child: roomId == null
          ? const SizedBox(width: double.infinity)
          : RoomTheme(
              child: MiniPlayer(
                roomId: roomId,
                status: status,
                failure: failure,
                errorMessage: errorMessage,
                roomName: roomName,
                nowPlaying: nowPlaying,
              ),
            ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    required this.roomId,
    required this.status,
    required this.failure,
    required this.errorMessage,
    required this.roomName,
    required this.nowPlaying,
    super.key,
  });

  final String roomId;
  final RoomConnectionStatus status;
  final RoomFailure? failure;
  final String? errorMessage;
  final String? roomName;
  final NowPlaying? nowPlaying;

  static const _cover = 48.0;

  static double heightOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style) =>
        scaler.scale(style.fontSize!) * style.height!;
    final text =
        line(AlistenTypography.bodyStrong) +
        _lineGap +
        line(AlistenTypography.secondary) +
        // 补偿文字排版后的取整误差。
        1;
    return math.max(_cover, text) + 2 * (AlistenSpacing.xs + _stroke);
  }

  static const _lineGap = AlistenSpacing.xxs / 2;

  static const _stroke = 1.0;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final nowPlaying = this.nowPlaying;
    final meta = nowPlaying?.entry.meta;
    final closable =
        failure == RoomFailure.notFound || failure == RoomFailure.outdated;
    final (subtitle, subtitleInk, lyricsFit) = switch ((status, meta)) {
      _ when failure != null => (
        errorMessage ?? '与房间的连接已经停止',
        colors.danger,
        false,
      ),
      (RoomConnectionStatus.connecting, _) => (
        '正在连接房间…',
        colors.warning,
        false,
      ),
      (RoomConnectionStatus.reconnecting, _) => (
        '连接中断，正在重连…',
        colors.warning,
        false,
      ),
      (_, null) => ('房间暂时没有播放', colors.onGlassMuted, false),
      (_, final meta?) => (
        [?roomName, meta.artist].where((part) => part.isNotEmpty).join(' · '),
        colors.onGlassMuted,
        true,
      ),
    };
    void open() => context.go('/r/$roomId');
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -_openVelocity) open();
      },
      child: Pressable(
        onPressed: open,
        semanticLabel: '打开房间${roomName == null ? '' : ' $roomName'}',
        focusRadius: BorderRadius.circular(AlistenRadii.md),
        // 浮在所有页面之外，上层没有默认文字样式。
        child: DefaultTextStyle(
          style: AlistenTypography.body.copyWith(color: colors.onGlass),
          child: Container(
            height: heightOf(context),
            decoration: BoxDecoration(
              color: colors.raised,
              borderRadius: BorderRadius.circular(AlistenRadii.md),
              border: Border.all(color: colors.glassStroke, width: _stroke),
              // 浅色页面上的深色条本身已足够醒目，阴影只用来托起它。
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: AlistenSpacing.lg,
                  offset: const Offset(0, AlistenSpacing.xxs),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AlistenSpacing.xs,
                    AlistenSpacing.xs,
                    AlistenSpacing.xxs,
                    AlistenSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      CoverArt(
                        url: meta?.coverUrl,
                        size: _cover,
                        heroTag: nowPlaying == null
                            ? null
                            : 'cover-${nowPlaying.entry.id}',
                      ),
                      const SizedBox(width: AlistenSpacing.sm),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              meta?.title ?? roomName ?? '房间',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AlistenTypography.weighted(
                                AlistenTypography.bodyStrong,
                                FontWeight.w700,
                              ).copyWith(color: colors.onGlass),
                            ),
                            const SizedBox(height: _lineGap),
                            _Subtitle(
                              text: subtitle,
                              color: subtitleInk,
                              lyricsFit: lyricsFit,
                            ),
                          ],
                        ),
                      ),
                      if (closable)
                        const _Close()
                      else if (nowPlaying != null)
                        const _LocalPause(),
                    ],
                  ),
                ),
                // 只占底边的直线段，不被圆角切掉。
                if (nowPlaying != null)
                  const Positioned(
                    left: AlistenRadii.md,
                    right: AlistenRadii.md,
                    bottom: 0,
                    child: MiniPlayerProgress(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 单位为逻辑像素每秒。
const _openVelocity = 250.0;

class _Subtitle extends ConsumerWidget {
  const _Subtitle({
    required this.text,
    required this.color,
    required this.lyricsFit,
  });

  final String text;
  final Color color;

  /// 连接出问题时要说明原因，不让歌词盖住。
  final bool lyricsFit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyric = lyricsFit ? ref.watch(currentLyricProvider) : null;
    final shown = lyric ?? text;
    return AnimatedSwitcher(
      duration: AlistenDurations.of(context, AlistenDurations.short),
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, ?current],
      ),
      child: Text(
        shown,
        key: ValueKey(shown),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AlistenTypography.secondary.copyWith(color: color),
      ),
    );
  }
}

class _Close extends ConsumerWidget {
  const _Close();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconCircleButton(
      icon: AlistenIcons.x,
      semanticLabel: '关闭',
      style: IconCircleButtonStyle.plain,
      iconSize: AlistenSizes.iconLg,
      onPressed: () =>
          unawaited(ref.read(roomControllerProvider.notifier).leaveRoom()),
    );
  }
}

class _LocalPause extends ConsumerWidget {
  const _LocalPause();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      playbackControllerProvider.select((playback) => playback.status),
    );
    // 两首之间暂停会挂起下一首，本机无法播放时按钮也无效：
    // 这两种情况只显示说明，不提供按钮。
    if (isPlaybackControlInert(status)) {
      final note = localPlaybackNote(status)!;
      return Semantics(
        container: true,
        label: note.text,
        child: SizedBox.square(
          dimension: AlistenSizes.minTouchTarget,
          child: Icon(
            note.icon,
            size: AlistenSizes.iconLg,
            color: AlistenColors.of(context).onGlassMuted,
          ),
        ),
      );
    }
    final offerPlay =
        status == LocalPlaybackStatus.paused ||
        status == LocalPlaybackStatus.error;
    return IconCircleButton(
      icon: offerPlay ? AlistenIcons.playFill : AlistenIcons.pauseFill,
      semanticLabel: offerPlay ? '恢复本机播放' : '暂停本机播放',
      style: IconCircleButtonStyle.plain,
      iconSize: AlistenSizes.iconLg,
      onPressed: () =>
          ref.read(playbackControllerProvider.notifier).toggleLocalPause(),
    );
  }
}

@visibleForTesting
class MiniPlayerProgress extends ConsumerWidget {
  const MiniPlayerProgress({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (position, duration) = ref.watch(
      playbackControllerProvider.select(
        (playback) => (playback.positionMs, playback.durationMs),
      ),
    );
    if (duration <= 0) return const SizedBox.shrink();
    final colors = AlistenColors.of(context);
    return CustomPaint(
      size: const Size.fromHeight(AlistenSizes.progressTrack / 2),
      painter: _ProgressPainter(
        played: (position / duration).clamp(0.0, 1.0),
        ink: colors.onGlass,
        track: colors.onGlass.withValues(alpha: _trackAlpha),
        glow: colors.glow,
        rtl: Directionality.of(context) == TextDirection.rtl,
      ),
    );
  }
}

/// 未播放的部分只是一道淡痕，与边框一起看仍是一个整体。
const _trackAlpha = 0.14;

class _ProgressPainter extends CustomPainter {
  _ProgressPainter({
    required this.played,
    required this.ink,
    required this.track,
    required this.glow,
    required this.rtl,
  });

  final double played;
  final Color ink;
  final Color track;
  final Color glow;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    if (played <= 0) return;
    final width = size.width * played;
    final filled = rtl
        ? Rect.fromLTWH(size.width - width, 0, width, size.height)
        : Rect.fromLTWH(0, 0, width, size.height);
    canvas.drawRect(filled, Paint()..color = glow);
    paintProgressHead(
      canvas,
      Offset(rtl ? filled.left : filled.right, size.height / 2),
      ink: ink,
      glow: glow,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter oldDelegate) {
    return oldDelegate.played != played ||
        oldDelegate.ink != ink ||
        oldDelegate.track != track ||
        oldDelegate.glow != glow ||
        oldDelegate.rtl != rtl;
  }
}
