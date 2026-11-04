import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/clipboard_link_controller.dart';
import 'package:alisten/features/search/application/pending_share_controller.dart';
import 'package:alisten/features/search/application/pick_controller.dart';
import 'package:alisten/features/search/application/pickable_link.dart';
import 'package:alisten/features/search/application/search_controller.dart';
import 'package:alisten/features/search/application/search_state.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:alisten/features/search/presentation/share_link_card.dart';
import 'package:alisten/features/search/presentation/song_row.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/chip_pill.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/cover_backdrop.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/page_glow.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/section_header.dart';
import 'package:alisten/shared/ui/segmented_pills.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _sources = [
  PillSegment(value: TrackSource.qq, label: 'QQ 音乐'),
  PillSegment(value: TrackSource.netease, label: '网易云'),
];

const _views = [
  (SearchView.all, '全部'),
  (SearchView.tracks, '歌曲'),
  (SearchView.playlists, '歌单'),
];

String _sourceName(TrackSource source) => switch (source) {
  TrackSource.qq => 'QQ 音乐',
  TrackSource.netease => '网易云',
  TrackSource.bilibili => 'B 站',
  TrackSource.link => '链接',
};

const _loadMoreDistance = 600.0;

// 手机屏幕上每行正好放下两个歌单。
const _playlistTileWidth = 200.0;

const _headerPadding = EdgeInsets.fromLTRB(
  AlistenSpacing.page,
  AlistenSpacing.xl,
  AlistenSpacing.page,
  AlistenSpacing.xs,
);

// 点歌之后页面不关闭，方便接连点几首。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    required this.onResult,
    required this.onNotice,
    required this.onOpenPlaylist,
    required this.onShowQueue,
    required this.onOpenRoom,
    super.key,
  });

  /// 在比页面存活更久的地方报告点歌结果，例如提示。
  final QueueResultCallback onResult;

  /// 在比页面存活更久的地方报告出错信息。
  final ValueChanged<String> onNotice;

  /// 歌单页打开在本页之上，本页保持原样。
  final ValueChanged<PlaylistSummary> onOpenPlaylist;

  final VoidCallback onShowQueue;

  /// 以路由打开当前服务器上的另一个房间，会退出当前房间。
  final ValueChanged<String> onOpenRoom;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _input;
  final _focus = FocusNode();

  SearchController get _search => ref.read(searchControllerProvider.notifier);

  static bool _home(SearchState search) =>
      search.view == SearchView.recommend || search.keyword.isEmpty;

  @override
  void initState() {
    super.initState();
    final search = ref.read(searchControllerProvider);
    final home = _home(search);
    _input = TextEditingController(text: home ? '' : search.keyword);
    // 等首次构建之后再检查：构建时已监听剪贴板提示，它才会在页面显示期间一直
    // 保留。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(clipboardLinkControllerProvider.notifier).check());
    });
    if (!home) return;
    // 不能在页面构建期间修改状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (search.view != SearchView.recommend) {
        _showHome();
      } else if (search.status is SearchFailed ||
          search.status is SearchPartial) {
        unawaited(_search.refreshRecommendations());
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _showHome({TrackSource? source}) {
    unawaited(_search.submit('', source: source, view: SearchView.recommend));
  }

  String get _keyword {
    final text = _input.text.trim();
    return linkOf(text) == null ? text : '';
  }

  void _onChanged(String text) {
    setState(() {});
    if (text.trim().isEmpty && !_home(ref.read(searchControllerProvider))) {
      _showHome();
    }
  }

  void _submit() {
    final keyword = _keyword;
    if (keyword.isNotEmpty) unawaited(_search.submit(keyword));
  }

  // 调用时输入框已清空，随后重新获得焦点。
  void _clear() {
    setState(() {});
    _showHome();
  }

  // 在新音源里搜索上次提交的关键词；尚未提交的输入既不搜索也不记录。
  void _changeSource(TrackSource source) {
    if (_home(ref.read(searchControllerProvider))) {
      _showHome(source: source);
    } else {
      unawaited(_search.changeSource(source));
    }
  }

  void _changeView(SearchView view) {
    unawaited(_search.changeView(view));
  }

  void _searchAgain(SearchRecord record) {
    _input.value = TextEditingValue(
      text: record.query,
      selection: TextSelection.collapsed(offset: record.query.length),
    );
    _focus.unfocus();
    setState(() {});
    unawaited(
      _search.submit(
        record.query,
        source: record.source,
        view: switch (record.category) {
          SearchCategory.all => SearchView.all,
          SearchCategory.tracks => SearchView.tracks,
          SearchCategory.playlists => SearchView.playlists,
        },
      ),
    );
  }

  Future<void> _clearHistory() async {
    final confirmed = await showConfirmSheet(
      context,
      title: '清空最近搜索？',
      message: '这台设备上记下的搜索词会全部删除。',
      confirmLabel: '清空',
      confirmIcon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !mounted) return;
    unawaited(_search.clearHistory());
  }

  void _pick(Track track, String title) {
    unawaited(pickSong(ref, widget.onResult, track, title));
  }

  void _open(String pageUrl) {
    unawaited(openOriginalPage(pageUrl, widget.onNotice));
  }

  // 上一页加载失败时不自动加载，等用户点“重试”。
  bool _onScroll(int depth, ScrollMetrics metrics) {
    // 只看页面本身的列表，忽略其中横向滚动的卡片行和内嵌的状态视图。
    if (depth != 0 || metrics.extentAfter > _loadMoreDistance) return false;
    final search = ref.read(searchControllerProvider);
    if (search.hasMore && search.status is SearchLoaded) {
      unawaited(_search.loadMore());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);
    final text = _input.text.trim();
    final typed = linkOf(text);
    final home = _home(search);
    final List<Widget> body;
    if (typed != null) {
      body = [_typedLink(text)];
    } else if (home) {
      body = _homeSlivers(search);
    } else {
      body = _resultSlivers(search);
    }
    final offers = _offers(typed);
    return AlistenScaffold(
      background: const PageGlow(),
      // 提示显示在输入框和筛选项下方，以免搜下一首歌时挡住它们。
      topBar: ToastClearance(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AlistenTopBar(
              leading: IconCircleButton(
                // 页面从底部升起时，收起的方向是向下。
                icon: ModalRoute.of(context)?.fullscreenDialog ?? false
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.arrow_back_rounded,
                semanticLabel: '返回房间',
                style: IconCircleButtonStyle.plain,
                onPressed: () => unawaited(Navigator.maybePop(context)),
              ),
              title: '点歌',
              actions: [_PickedCount(onPressed: widget.onShowQueue)],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AlistenSpacing.md,
                AlistenSpacing.xxs,
                AlistenSpacing.md,
                0,
              ),
              child: AlistenTextField(
                controller: _input,
                focusNode: _focus,
                autofocus: true,
                hint: '搜歌名、歌手，或粘贴链接',
                icon: Icons.search_rounded,
                pill: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (_) => _submit(),
                onClear: _clear,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlistenSpacing.md,
              ),
              child: _Filters(
                source: search.source,
                view: home || typed != null ? null : search.view,
                onSource: _changeSource,
                onView: _changeView,
              ),
            ),
            const PickUnavailableNotice(),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) =>
                  _onScroll(notification.depth, notification.metrics),
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (notification) =>
                    _onScroll(notification.depth, notification.metrics),
                child: CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    ...offers,
                    ...body,
                    // 填满页面的状态视图自己居中，不需要底部留白。
                    if (body.last is! SliverFillRemaining)
                      SliverPadding(
                        padding: EdgeInsets.only(
                          bottom:
                              MediaQuery.paddingOf(context).bottom +
                              AlistenSpacing.xl,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _offers(String? typed) {
    final pending = ref.watch(pendingShareControllerProvider);
    final clipboard = ref.watch(clipboardLinkControllerProvider);
    final shares = ref.read(pendingShareControllerProvider.notifier);
    final clipboardOffer = ref.read(clipboardLinkControllerProvider.notifier);
    final shared = pending?.share?.link;
    return [
      if (pending != null)
        _linkCardSliver(
          ShareLinkCard(
            heading: sharedLinkHeading,
            share: pending.share,
            resolving: !pending.resolved,
            onResult: widget.onResult,
            onPicked: () => shares.dismiss(pending.id),
            onDismiss: () => shares.dismiss(pending.id),
          ),
        ),
      if (clipboard != null &&
          clipboard.link != shared &&
          clipboard.link != typed)
        _linkCardSliver(
          ShareLinkCard(
            heading: clipboard.otherRoom == null ? '点剪贴板里的链接' : '剪贴板里的房间链接',
            share: clipboard,
            onResult: widget.onResult,
            onPicked: clipboardOffer.dismiss,
            onDismiss: clipboardOffer.dismiss,
            onEnterRoom: widget.onOpenRoom,
          ),
        ),
    ];
  }

  Widget _typedLink(String text) {
    final kind = ref.watch(
      roomControllerProvider.select((room) => room.snapshot?.room.kind),
    );
    final share = ref.watch(typedLinkProvider(text));
    final following = share?.unfollowed ?? false;
    final otherRoom = share?.otherRoom;
    final reason = share == null
        ? unrecognizedText
        : following || otherRoom != null
        ? null
        : unpickableReason(share, kind);
    if (reason == null) {
      return _linkCardSliver(
        ShareLinkCard(
          heading: following
              ? '这条链接'
              : otherRoom == null
              ? '点这条链接'
              : '房间链接',
          share: share,
          resolving: following,
          onResult: widget.onResult,
          onEnterRoom: widget.onOpenRoom,
        ),
      );
    }
    return SliverFillRemaining(
      child: EmptyState(
        icon: Icons.link_off_rounded,
        title: reason,
        message: switch (share?.problem) {
          LinkProblem.notSong => '歌单、专辑和歌手的链接不能直接点，可以搜索歌名。',
          LinkProblem.roomLink => null,
          null when share?.track?.source == TrackSource.link =>
            '其他网站的链接可以在常驻房间里点。',
          _ => '检查链接是否完整，或者直接搜索歌名。',
        },
      ),
    );
  }

  Widget _linkCardSliver(Widget card) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AlistenSpacing.page,
        AlistenSpacing.md,
        AlistenSpacing.page,
        0,
      ),
      sliver: SliverToBoxAdapter(child: card),
    );
  }

  List<Widget> _homeSlivers(SearchState search) {
    final recent = search.recentSearches;
    return [
      if (recent.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            '最近搜索',
            padding: _headerPadding,
            trailing: PillButton(
              label: '清空',
              style: PillButtonStyle.ghost,
              onPressed: () => unawaited(_clearHistory()),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.md),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: AlistenSpacing.xs,
              children: [
                for (final record in recent)
                  ChipPill(
                    label: record.query,
                    icon: Icons.history_rounded,
                    onPressed: () => _searchAgain(record),
                  ),
              ],
            ),
          ),
        ),
      ],
      SliverToBoxAdapter(
        child: SectionHeader(
          '为你推荐',
          padding: _headerPadding,
          trailing: search.loading
              ? const SizedBox.square(
                  dimension: AlistenSizes.minTouchTarget,
                  child: Center(child: BusyIndicator(semanticLabel: '正在推荐')),
                )
              : IconCircleButton(
                  icon: Icons.refresh_rounded,
                  semanticLabel: '换一批推荐',
                  style: IconCircleButtonStyle.plain,
                  onPressed: () => unawaited(_search.refreshRecommendations()),
                ),
        ),
      ),
      SliverToBoxAdapter(
        child: _Recommendations(
          search: search,
          onPick: _pick,
          onOpen: _open,
          onRetry: () => unawaited(_search.refreshRecommendations()),
        ),
      ),
    ];
  }

  List<Widget> _resultSlivers(SearchState search) {
    final status = search.status;
    if (search.tracks.isEmpty && search.playlists.isEmpty) {
      return [
        SliverFillRemaining(
          child: switch (status) {
            SearchIdle() || SearchLoading() => const Center(
              child: BusyIndicator(
                size: AlistenSizes.iconLg,
                semanticLabel: '正在搜索',
              ),
            ),
            SearchFailed(:final message) ||
            SearchPartial(:final message) => Semantics(
              liveRegion: true,
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: message,
                action: PillButton(
                  label: '重试',
                  icon: Icons.refresh_rounded,
                  style: PillButtonStyle.secondary,
                  onPressed: () => unawaited(_search.retry()),
                ),
              ),
            ),
            SearchLoaded() => _nothingFound(search),
          },
        ),
      ];
    }
    final retry = status is SearchPartial
        ? _InlineRetry(
            message: status.message,
            onRetry: () => unawaited(_search.retry()),
          )
        : null;
    return switch (search.view) {
      SearchView.all || SearchView.recommend => [
        if (retry != null) SliverToBoxAdapter(child: retry),
        ..._overview(search),
      ],
      SearchView.tracks => [
        const SliverPadding(padding: EdgeInsets.only(top: AlistenSpacing.xs)),
        SliverList.builder(
          itemCount: search.tracks.length,
          itemBuilder: (context, index) =>
              SongRow(song: search.tracks[index], onPick: _pick, onOpen: _open),
        ),
        SliverToBoxAdapter(
          child: _More(search: search, retry: retry),
        ),
      ],
      SearchView.playlists => [
        const SliverPadding(padding: EdgeInsets.only(top: AlistenSpacing.sm)),
        _PlaylistGrid(
          playlists: search.playlists,
          onOpen: widget.onOpenPlaylist,
        ),
        SliverToBoxAdapter(
          child: _More(search: search, retry: retry),
        ),
      ],
    };
  }

  List<Widget> _overview(SearchState search) {
    final best = search.bestMatch;
    final songs = search.overviewTracks;
    final playlists = canOpenPlaylists(search.source)
        ? search.overviewPlaylists
        : const <PlaylistSummary>[];
    return [
      if (best != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AlistenSpacing.md,
            AlistenSpacing.sm,
            AlistenSpacing.md,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _BestMatch(song: best, onPick: _pick, onOpen: _open),
          ),
        ),
      if (songs.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            '歌曲',
            padding: _headerPadding,
            trailing: search.results.tracksTotal > songs.length + 1
                ? _SeeAll(onPressed: () => _changeView(SearchView.tracks))
                : null,
          ),
        ),
        SliverList.builder(
          itemCount: songs.length,
          itemBuilder: (context, index) =>
              SongRow(song: songs[index], onPick: _pick, onOpen: _open),
        ),
      ],
      if (playlists.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            '歌单',
            padding: _headerPadding,
            trailing: search.results.playlistsTotal > playlists.length
                ? _SeeAll(onPressed: () => _changeView(SearchView.playlists))
                : null,
          ),
        ),
        _PlaylistGrid(playlists: playlists, onOpen: widget.onOpenPlaylist),
      ],
    ];
  }

  Widget _nothingFound(SearchState search) {
    final other = search.source == TrackSource.qq
        ? TrackSource.netease
        : TrackSource.qq;
    final playlists = search.view == SearchView.playlists;
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: '没有找到“${search.keyword}”',
      message: playlists
          ? '没有相关的歌单，换个关键词试试。'
          : '换个关键词试试，或者到${_sourceName(other)}找找。',
      action: playlists
          ? null
          : PillButton(
              label: '在${_sourceName(other)}搜索',
              icon: Icons.swap_horiz_rounded,
              style: PillButtonStyle.secondary,
              onPressed: () => _changeSource(other),
            ),
    );
  }
}

class _PickedCount extends ConsumerWidget {
  const _PickedCount({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final added = ref.watch(
      pickControllerProvider.select((picks) => picks.added),
    );
    final colors = AlistenColors.of(context);
    return AnimatedSwitcher(
      duration: AlistenDurations.of(context, AlistenDurations.medium),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: animation.drive(CurveTween(curve: AlistenCurves.bounce)),
          child: child,
        ),
      ),
      child: added == 0
          ? const SizedBox.shrink()
          : Pressable(
              key: ValueKey(added),
              onPressed: onPressed,
              semanticLabel: '已点 $added 首，查看队列',
              focusRadius: BorderRadius.circular(AlistenRadii.pill),
              child: ExcludeSemantics(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AlistenSizes.minTouchTarget,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: colors.brandGradient,
                        borderRadius: BorderRadius.circular(AlistenRadii.pill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AlistenSpacing.sm,
                          AlistenSpacing.xs,
                          AlistenSpacing.md,
                          AlistenSpacing.xs,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.queue_music_rounded,
                              size: AlistenSizes.iconSm,
                              color: colors.onBrand,
                            ),
                            const SizedBox(width: AlistenSpacing.xxs),
                            Text(
                              '已点 $added 首',
                              style: AlistenTypography.weighted(
                                AlistenTypography.secondary,
                                FontWeight.w700,
                              ).copyWith(color: colors.onBrand),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.source,
    required this.view,
    required this.onSource,
    required this.onView,
  });

  final TrackSource source;
  final SearchView? view;
  final ValueChanged<TrackSource> onSource;
  final ValueChanged<SearchView> onView;

  @override
  Widget build(BuildContext context) {
    final view = this.view;
    final width = MediaQuery.textScalerOf(context)
        .scale(AlistenSizes.twoChoiceWidth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: AlistenSpacing.sm,
            bottom: AlistenSpacing.xxs,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Semantics(
              container: true,
              label: '音乐来源',
              child: SegmentedPills<TrackSource>(
                segments: _sources,
                selected: source,
                onChanged: (chosen) {
                  if (chosen != source) onSource(chosen);
                },
              ),
            ),
          ),
        ),
        if (view != null)
          Wrap(
            spacing: AlistenSpacing.xs,
            children: [
              for (final (choice, label) in _views)
                if (choice != SearchView.playlists || canOpenPlaylists(source))
                  ChipPill(
                    label: label,
                    selected: view == choice,
                    onPressed: () {
                      if (view != choice) onView(choice);
                    },
                  ),
            ],
          ),
      ],
    );
  }
}

class _Recommendations extends StatelessWidget {
  const _Recommendations({
    required this.search,
    required this.onPick,
    required this.onOpen,
    required this.onRetry,
  });

  final SearchState search;
  final PickSong onPick;
  final ValueChanged<String> onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final songs = search.recommendations;
    final status = search.status;
    if (songs.isEmpty) {
      return switch (status) {
        SearchFailed(:final message) || SearchPartial(:final message) =>
          _InlineRetry(message: message, onRetry: onRetry),
        SearchLoaded() => const _Note(
          icon: Icons.auto_awesome_rounded,
          text: '还没有推荐。房间里多播几首网易云的歌，这里就会有了。',
        ),
        SearchIdle() || SearchLoading() => const SizedBox(
          height: AlistenSizes.cardCover,
          child: Center(child: BusyIndicator(size: AlistenSizes.iconLg)),
        ),
      };
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, song) in songs.indexed) ...[
            if (index > 0) const SizedBox(width: AlistenSpacing.sm),
            _RecommendationCard(song: song, onPick: onPick, onOpen: onOpen),
          ],
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.song,
    required this.onPick,
    required this.onOpen,
  });

  final TrackSummary song;
  final PickSong onPick;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final meta = song.meta;
    return SizedBox(
      width: AlistenSizes.cardCover,
      child: OpenOnLongPress(
        pageUrl: meta.pageUrl,
        onOpen: onOpen,
        radius: AlistenRadii.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CoverArt(
                  url: meta.coverUrl,
                  size: AlistenSizes.cardCover,
                  radius: AlistenRadii.md,
                ),
                PositionedDirectional(
                  end: 0,
                  bottom: 0,
                  child: PickControl(
                    track: song.track,
                    title: meta.title,
                    onPick: onPick,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AlistenSpacing.xs),
            Text(
              meta.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AlistenTypography.bodyStrong.copyWith(
                color: colors.onGlass,
              ),
            ),
            Text(
              meta.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AlistenTypography.secondary.copyWith(
                color: colors.onGlassMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BestMatch extends StatelessWidget {
  const _BestMatch({
    required this.song,
    required this.onPick,
    required this.onOpen,
  });

  final TrackSummary song;
  final PickSong onPick;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final meta = song.meta;
    final shape = BorderRadius.circular(AlistenRadii.lg);
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: shape,
        border: Border.all(color: colors.glassStroke),
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: Stack(
          children: [
            Positioned.fill(
              child: CoverBackdrop(
                url: meta.coverUrl,
                child: ColoredBox(color: colors.glassFill),
              ),
            ),
            OpenOnLongPress(
              pageUrl: meta.pageUrl,
              onOpen: onOpen,
              radius: AlistenRadii.lg,
              child: Padding(
                padding: const EdgeInsets.all(AlistenSpacing.md),
                child: Row(
                  children: [
                    CoverArt(
                      url: meta.coverUrl,
                      size: AlistenSizes.featureCover,
                      radius: AlistenRadii.md,
                    ),
                    const SizedBox(width: AlistenSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '最佳匹配',
                            style: AlistenTypography.caption.copyWith(
                              color: colors.onGlassMuted,
                            ),
                          ),
                          const SizedBox(height: AlistenSpacing.xxs),
                          Text(
                            meta.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AlistenTypography.weighted(
                              AlistenTypography.title,
                              FontWeight.w700,
                            ).copyWith(color: colors.onGlass),
                          ),
                          Text(
                            songSubtitle(meta),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AlistenTypography.secondary.copyWith(
                              color: colors.onGlassMuted,
                            ),
                          ),
                          const SizedBox(height: AlistenSpacing.sm),
                          PickControl(
                            track: song.track,
                            title: meta.title,
                            onPick: onPick,
                            wide: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistGrid extends StatelessWidget {
  const _PlaylistGrid({required this.playlists, required this.onOpen});

  final List<PlaylistSummary> playlists;
  final ValueChanged<PlaylistSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.md),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final across = math.max(
            2,
            (constraints.crossAxisExtent / _playlistTileWidth).floor(),
          );
          final rows = (playlists.length / across).ceil();
          return SliverList.builder(
            itemCount: rows,
            itemBuilder: (context, row) => Padding(
              padding: EdgeInsets.only(
                bottom: row == rows - 1 ? 0 : AlistenSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < across; column++) ...[
                    if (column > 0) const SizedBox(width: AlistenSpacing.sm),
                    Expanded(
                      child: row * across + column < playlists.length
                          ? _PlaylistTile(
                              playlist: playlists[row * across + column],
                              onOpen: onOpen,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist, required this.onOpen});

  final PlaylistSummary playlist;
  final ValueChanged<PlaylistSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Pressable(
      onPressed: () => onOpen(playlist),
      focusRadius: BorderRadius.circular(AlistenRadii.md),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverArt(
              url: playlist.coverUrl,
              size: constraints.maxWidth,
              radius: AlistenRadii.md,
            ),
            const SizedBox(height: AlistenSpacing.xs),
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AlistenTypography.bodyStrong.copyWith(
                color: colors.onGlass,
              ),
            ),
            Text(
              playlist.creator.isEmpty
                  ? '${playlist.trackCount} 首'
                  : '${playlist.trackCount} 首 · ${playlist.creator}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AlistenTypography.secondary.copyWith(
                color: colors.onGlassMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _More extends StatelessWidget {
  const _More({required this.search, required this.retry});

  final SearchState search;
  final Widget? retry;

  @override
  Widget build(BuildContext context) {
    final retry = this.retry;
    if (retry != null) return retry;
    if (!search.hasMore && !search.loading) return const SizedBox.shrink();
    return const SizedBox(
      height: AlistenSizes.largeTouchTarget,
      child: Center(child: BusyIndicator(semanticLabel: '正在加载更多')),
    );
  }
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PillButton(
      label: '全部',
      style: PillButtonStyle.ghost,
      onPressed: onPressed,
    );
  }
}

class _InlineRetry extends StatelessWidget {
  const _InlineRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlistenSpacing.md,
        vertical: AlistenSpacing.xs,
      ),
      child: Semantics(
        liveRegion: true,
        child: GlassPanel(
          padding: const EdgeInsets.fromLTRB(
            AlistenSpacing.md,
            AlistenSpacing.xxs,
            AlistenSpacing.xxs,
            AlistenSpacing.xxs,
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: AlistenSizes.iconSm,
                color: colors.danger,
              ),
              const SizedBox(width: AlistenSpacing.xs),
              Expanded(
                child: Text(
                  message,
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlass,
                  ),
                ),
              ),
              PillButton(
                label: '重试',
                style: PillButtonStyle.ghost,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = AlistenColors.of(context).onGlassMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.page),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: AlistenSizes.iconSm, color: muted),
          ),
          const SizedBox(width: AlistenSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: AlistenTypography.secondary.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}
