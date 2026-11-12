import 'dart:async';

import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:alisten/features/search/presentation/song_row.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const sharedLinkHeading = '点分享的链接';

// 应用不带各平台的标志，徽标上用文字代替。
String platformLabel(LinkPlatform platform) => switch (platform) {
  LinkPlatform.netease => '网易云',
  LinkPlatform.qq => 'QQ 音乐',
  LinkPlatform.bilibili => 'B 站',
  LinkPlatform.web => '链接',
};

class ShareLinkCard extends ConsumerWidget {
  const ShareLinkCard({
    required this.heading,
    required this.share,
    required this.onResult,
    this.resolving = false,
    this.roomName,
    this.onPicked,
    this.onDismiss,
    this.onEnterRoom,
    this.framed = true,
    this.compact = false,
    super.key,
  });

  final String heading;

  /// 文本里没有链接时为 null；[resolving] 期间还没识别出任何内容时也为 null。
  final ResolvedShare? share;

  final bool resolving;

  final String? roomName;

  /// 在比卡片存活更久的地方报告点歌结果。
  final QueueResultCallback onResult;

  /// 房间确认收下这首歌之后才调用。
  final VoidCallback? onPicked;

  /// 为 null 时不显示关闭按钮。
  final VoidCallback? onDismiss;

  /// 链接是 [ResolvedShare.linkRoute] 时，以它的路由调用。
  final ValueChanged<String>? onEnterRoom;

  /// 放在面板里时为 false，面板本身已有底板。
  final bool framed;

  /// 能点的歌只占一行：徽标、歌名或链接、点歌和关闭。房间、歌单链接和点不了的
  /// 链接仍显示完整卡片，它们的说明放不进一行。
  final bool compact;

  Future<void> _pick(WidgetRef ref, Track track, String title) async {
    final picked = onPicked;
    final result = await pickSong(ref, onResult, track, title);
    if (result is MutationSucceeded) picked?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    final kind = ref.watch(
      roomControllerProvider.select((room) => room.snapshot?.room.kind),
    );
    final share = this.share;
    final track = share?.track;
    final name = share?.title;
    final reason = resolving
        ? null
        : share == null
        ? noLinkText
        : unpickableReason(share, kind);
    final muted = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );

    final linkRoute = share?.linkRoute;
    final playlistLink = share?.problem == LinkProblem.sharedPlaylistLink;
    final enterRoom = onEnterRoom;
    final inRoom = ref.watch(
      roomControllerProvider.select((room) => room.activeRoomId != null),
    );
    final Widget action;
    if (linkRoute != null && enterRoom != null && !resolving) {
      // 打开歌单不离开房间，所以没有“离开当前房间并进入”的说法。
      action = PillButton(
        label: playlistLink
            ? '打开这个歌单'
            : inRoom
            ? '离开当前房间并进入'
            : '进入这个房间',
        icon: playlistLink
            ? Icons.queue_music_rounded
            : Icons.meeting_room_rounded,
        large: true,
        expand: true,
        onPressed: () => enterRoom(linkRoute),
      );
    } else if (resolving) {
      action = Row(
        children: [
          BusyIndicator(size: AlistenSizes.iconSm, color: colors.onGlassMuted),
          const SizedBox(width: AlistenSpacing.xs),
          Expanded(child: Text('正在识别链接', style: muted)),
        ],
      );
    } else if (reason != null || track == null) {
      action = Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          liveRegion: true,
          child: StatusPill(
            label: reason ?? unrecognizedText,
            icon: Icons.link_off_rounded,
            tone: StatusTone.warning,
          ),
        ),
      );
    } else {
      final pick = PickControl(
        track: track,
        title: name ?? '',
        label: name != null
            ? '点歌《$name》'
            : track.source == TrackSource.link
            ? '点这条链接'
            : '点这首歌',
        wide: !compact,
        expand: !compact,
        tone: compact ? PickTone.tonal : PickTone.filled,
        onPick: (track, title) => unawaited(_pick(ref, track, title)),
      );
      if (compact) {
        return _CompactOffer(
          heading: heading,
          platform: share?.platform ?? LinkPlatform.web,
          text: name ?? _withoutScheme(share!.link),
          action: pick,
          onDismiss: onDismiss,
        );
      }
      action = pick;
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _PlatformBadge(platform: share?.platform ?? LinkPlatform.web),
            const SizedBox(width: AlistenSpacing.xs),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  heading,
                  style: AlistenTypography.weighted(
                    AlistenTypography.bodyStrong,
                    FontWeight.w700,
                  ).copyWith(color: colors.onGlass),
                ),
              ),
            ),
            if (onDismiss case final dismiss?)
              IconCircleButton(
                icon: Icons.close_rounded,
                semanticLabel: linkRoute == null
                    ? '不点这条链接'
                    : playlistLink
                    ? '不打开这个歌单'
                    : '不进入这个房间',
                style: IconCircleButtonStyle.plain,
                iconSize: AlistenSizes.iconSm,
                diameter: AlistenSizes.rowAction,
                onPressed: dismiss,
              ),
          ],
        ),
        if (name != null) ...[
          const SizedBox(height: AlistenSpacing.xs),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AlistenTypography.weighted(
              AlistenTypography.title,
              FontWeight.w700,
            ).copyWith(color: colors.onGlass),
          ),
        ],
        if (share != null)
          Padding(
            padding: EdgeInsets.only(top: name == null ? AlistenSpacing.xs : 0),
            child: Text(
              _withoutScheme(share.link),
              maxLines: name == null ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ),
        if (roomName case final room?) ...[
          const SizedBox(height: AlistenSpacing.xs),
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.meeting_room_rounded,
                  size: AlistenSizes.iconSm,
                  color: colors.onGlassMuted,
                ),
              ),
              const SizedBox(width: AlistenSpacing.xxs),
              Expanded(child: Text('点到「$room」', style: muted)),
            ],
          ),
        ],
        const SizedBox(height: AlistenSpacing.md),
        action,
      ],
    );
    if (!framed) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassFill,
        borderRadius: BorderRadius.circular(AlistenRadii.lg),
        border: Border.all(color: colors.glassStroke),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AlistenSpacing.md),
        child: content,
      ),
    );
  }
}

String _withoutScheme(String link) =>
    link.replaceFirst(RegExp('^https?://'), '');

class _CompactOffer extends StatelessWidget {
  const _CompactOffer({
    required this.heading,
    required this.platform,
    required this.text,
    required this.action,
    required this.onDismiss,
  });

  final String heading;
  final LinkPlatform platform;
  final String text;
  final Widget action;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    // 一行里放不下标题，读屏仍从标题读起，知道这一行从哪里来。
    return Semantics(
      container: true,
      label: heading,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.glassFill,
          borderRadius: BorderRadius.circular(AlistenRadii.md),
          border: Border.all(color: colors.glassStroke),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: AlistenSpacing.sm),
          child: Row(
            children: [
              // 徽标不随行变窄，最小的屏幕上 3 倍字号会把歌名挤没，所以限制缩放。
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 2,
                child: _PlatformBadge(platform: platform),
              ),
              const SizedBox(width: AlistenSpacing.xs),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlass,
                  ),
                ),
              ),
              action,
              if (onDismiss case final dismiss?)
                IconCircleButton(
                  icon: Icons.close_rounded,
                  semanticLabel: '不点这条链接',
                  style: IconCircleButtonStyle.plain,
                  iconSize: AlistenSizes.iconSm,
                  diameter: AlistenSizes.rowAction,
                  onPressed: dismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.platform});

  final LinkPlatform platform;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    // 不着色：旁边的点歌按钮已取了封面的颜色，两种颜色挨着会互相抢。
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.onGlass.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AlistenRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AlistenSpacing.sm,
          vertical: AlistenSpacing.xxs,
        ),
        child: Text(
          platformLabel(platform),
          style: AlistenTypography.weighted(
            AlistenTypography.caption,
            FontWeight.w700,
          ).copyWith(color: colors.onGlassMuted),
        ),
      ),
    );
  }
}
