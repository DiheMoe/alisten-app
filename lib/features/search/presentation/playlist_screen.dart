import 'dart:async';

import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/search/application/playlist_controller.dart';
import 'package:alisten/features/search/application/search_controller.dart';
import 'package:alisten/features/search/presentation/song_row.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/cover_backdrop.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({
    required this.source,
    required this.id,
    required this.onResult,
    required this.onNotice,
    this.saveAsMine,
    super.key,
  });

  final TrackSource source;
  final String id;

  /// 在比页面存活更久的地方报告点歌结果，例如提示。
  final QueueResultCallback onResult;

  /// 在比页面存活更久的地方报告出错信息。
  final ValueChanged<String> onNotice;

  /// 歌单功能依赖点歌，这里反过来依赖它会形成循环，所以按钮由 app 层传入。
  final Widget Function(String name)? saveAsMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = PlaylistKey(source, id);
    final playlist = ref.watch(playlistControllerProvider(key));
    // 从链接打开的歌单只知道 id，摘要只能从搜索结果里找。
    final summary = ref.watch(
      searchControllerProvider.select(
        (search) => search.playlistSummary(source, id),
      ),
    );
    void pick(Track track, String title) {
      unawaited(pickSong(ref, onResult, track, title));
    }

    void open(String pageUrl) {
      unawaited(openOriginalPage(pageUrl, onNotice));
    }

    final error = playlist.error;
    final detail = playlist.value;
    final Widget content;
    if (error != null && !playlist.isLoading) {
      content = SliverFillRemaining(
        child: Semantics(
          liveRegion: true,
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: playlistErrorMessage(error),
            action: PillButton(
              label: '重试',
              icon: Icons.refresh_rounded,
              style: PillButtonStyle.secondary,
              onPressed: ref
                  .read(playlistControllerProvider(key).notifier)
                  .retry,
            ),
          ),
        ),
      );
    } else if (detail == null) {
      content = const SliverFillRemaining(
        child: Center(
          child: BusyIndicator(
            size: AlistenSizes.iconLg,
            semanticLabel: '正在加载歌单',
          ),
        ),
      );
    } else if (detail.tracks.isEmpty) {
      content = const SliverFillRemaining(
        child: EmptyState(icon: Icons.queue_music_rounded, title: '这个歌单里还没有歌'),
      );
    } else {
      content = SliverList.builder(
        itemCount: detail.tracks.length,
        itemBuilder: (context, index) =>
            SongRow(song: detail.tracks[index], onPick: pick, onOpen: open),
      );
    }
    return AlistenScaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Header(
                  summary: summary,
                  songs: detail?.tracks.length,
                  saveAsMine: saveAsMine?.call(
                    summary == null || summary.name.trim().isEmpty
                        ? '导入的歌单'
                        : summary.name,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: PickUnavailableNotice()),
              content,
              if (content is! SliverFillRemaining)
                SliverPadding(
                  padding: EdgeInsets.only(
                    bottom:
                        MediaQuery.paddingOf(context).bottom +
                        AlistenSpacing.xl,
                  ),
                ),
            ],
          ),
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
}

class _Header extends StatelessWidget {
  const _Header({
    required this.summary,
    required this.songs,
    required this.saveAsMine,
  });

  final PlaylistSummary? summary;

  // 已加载的歌曲数，用于只知道 id 的歌单。
  final int? songs;
  final Widget? saveAsMine;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final surface = Theme.of(context).colorScheme.surface;
    final summary = this.summary;
    final songs = summary?.trackCount ?? this.songs;
    final facts = [
      if (summary != null && summary.creator.isNotEmpty) summary.creator,
      if (songs != null) '$songs 首',
      if (summary != null && summary.playCount > 0)
        '${_count(summary.playCount)}次播放',
    ];
    final description = summary?.description ?? '';
    // 顶栏浮在页面之上，内容从顶栏下方开始。
    final top =
        MediaQuery.paddingOf(context).top +
        AlistenSizes.minTouchTarget +
        AlistenSpacing.xs;
    return Stack(
      children: [
        Positioned.fill(child: CoverBackdrop(url: summary?.coverUrl)),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.5, 1],
                colors: [surface.withValues(alpha: 0), surface],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            AlistenSpacing.xxl,
            top,
            AlistenSpacing.xxl,
            AlistenSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: CoverArt(
                  url: summary?.coverUrl,
                  size: AlistenSizes.pageCover,
                  radius: AlistenRadii.lg,
                  glow: true,
                ),
              ),
              const SizedBox(height: AlistenSpacing.lg),
              Semantics(
                header: true,
                child: Text(
                  summary?.name ?? '歌单',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AlistenTypography.weighted(
                    AlistenTypography.title,
                    FontWeight.w700,
                  ).copyWith(color: colors.onGlass),
                ),
              ),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: AlistenSpacing.xs),
                Text(
                  facts.join(' · '),
                  textAlign: TextAlign.center,
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlassMuted,
                  ),
                ),
              ],
              if (description.isNotEmpty) ...[
                const SizedBox(height: AlistenSpacing.xs),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlassMuted,
                  ),
                ),
              ],
              if (saveAsMine case final save?) ...[
                const SizedBox(height: AlistenSpacing.md),
                Center(child: save),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// 例如 860、3.2万、1507万。
String _count(int count) {
  String short(double value) {
    final text = value.toStringAsFixed(value < 10 ? 1 : 0);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  if (count >= 100000000) return '${short(count / 100000000)}亿';
  if (count >= 10000) return '${short(count / 10000)}万';
  return '$count';
}
