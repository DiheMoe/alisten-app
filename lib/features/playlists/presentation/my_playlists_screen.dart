import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/playlist/playlist_date.dart';
import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/playlist/playlist_sort.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/application/playlist_view_controller.dart';
import 'package:alisten/features/playlists/presentation/import_link_sheet.dart';
import 'package:alisten/features/playlists/presentation/playlist_cover.dart';
import 'package:alisten/features/playlists/presentation/playlist_name_form.dart';
import 'package:alisten/features/playlists/presentation/playlist_states.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _truncatedText =
    '。文件里超过 $playlistFileTrackLimit 首，只导入了前 $playlistFileTrackLimit 首。';
const _maxCardWidth = 200.0;
const _gridGap = AlistenSpacing.md;

class MyPlaylistsScreen extends ConsumerStatefulWidget {
  const MyPlaylistsScreen({
    required this.onOpenPlaylist,
    required this.onOpenAccount,
    required this.onNotice,
    super.key,
  });

  /// 参数是歌单 ID。
  final ValueChanged<String> onOpenPlaylist;
  final VoidCallback onOpenAccount;

  /// 删除和导入的结果可能在页面关闭之后才提示。
  final void Function(ToastKind kind, String text, {Duration? duration})
  onNotice;

  @override
  ConsumerState<MyPlaylistsScreen> createState() => _MyPlaylistsScreenState();
}

class _MyPlaylistsScreenState extends ConsumerState<MyPlaylistsScreen> {
  bool _importing = false;

  MyPlaylistsController get _playlists =>
      ref.read(myPlaylistsControllerProvider.notifier);

  Future<void> _create() async {
    final playlists = _playlists;
    await showPlaylistNameSheet<MyPlaylist>(
      context,
      title: '新建歌单',
      confirmLabel: '创建',
      busyLabel: '创建',
      confirmIcon: AlistenIcons.plusBold,
      onSubmit: playlists.create,
    );
  }

  Future<void> _rename(MyPlaylist playlist) async {
    final playlists = _playlists;
    await showPlaylistNameSheet<void>(
      context,
      title: '重命名',
      initialName: playlist.name,
      confirmLabel: '保存',
      busyLabel: '保存',
      cancellable: false,
      onSubmit: (name) => playlists.rename(playlist, name),
    );
  }

  // 控制器和回调先取出：结果可能在页面关闭之后才返回。
  Future<void> _delete(MyPlaylist playlist) {
    final playlists = _playlists;
    final notice = widget.onNotice;
    return holdingWhile(context, myPlaylistsControllerProvider, () async {
      if (!await confirmPlaylistDelete(context, playlist)) return;
      reportPlaylistResult(notice, await playlists.delete(playlist));
    });
  }

  // 与 Web 相同，导入之后不打开新歌单。
  Future<void> _importFile() async {
    if (_importing) return;
    final playlists = _playlists;
    final notice = widget.onNotice;
    setState(() => _importing = true);
    try {
      await holdingWhile(context, myPlaylistsControllerProvider, () async {
        final result = await playlists.importFromFile();
        if (result == null) return;
        if (result case MutationSucceeded(
          value: (:final playlist, :final imported, :final truncated),
        )) {
          final done = '已导入 $imported 首到“${playlist.name}”';
          if (truncated) {
            notice(
              ToastKind.success,
              '$done$_truncatedText',
              duration: AlistenDurations.longToast,
            );
          } else {
            notice(ToastKind.success, done);
          }
        } else {
          reportPlaylistResult(notice, result);
        }
      });
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importLink() async {
    final playlists = _playlists;
    final notice = widget.onNotice;
    final imported = await showImportLinkSheet(
      context,
      onSubmit: playlists.importLink,
    );
    if (imported == null) return;
    notice(ToastKind.success, '已导入 ${imported.imported} 首');
    if (!mounted) return;
    widget.onOpenPlaylist(imported.playlist.id);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(myPlaylistsControllerProvider);
    final view = ref.watch(playlistViewProvider);
    final playlists = list.playlists;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final error = list.error;
    final Widget body;
    if (list.guest) {
      body = Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: PlaylistGuestState(onOpenAccount: widget.onOpenAccount),
      );
    } else if (playlists == null) {
      body = Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: error == null
            ? const PlaylistLoading()
            : PlaylistReadFailure(
                message: error,
                onRetry: () => unawaited(_playlists.retry()),
              ),
      );
    } else {
      body = _list(sortPlaylists(playlists, view.sort), view, list.loadedAtMs);
    }
    return AlistenScaffold(
      topBar: AlistenTopBar(
        leading: IconCircleButton(
          icon: AlistenIcons.arrowLeft,
          semanticLabel: '返回',
          style: IconCircleButtonStyle.plain,
          onPressed: () => unawaited(Navigator.maybePop(context)),
        ),
        title: '我的歌单',
      ),
      body: body,
    );
  }

  Widget _list(
    List<MyPlaylist> playlists,
    PlaylistViewPreference view,
    int nowMs,
  ) {
    // 已包含悬浮在安全区之上的迷你播放条。
    final bottom = MediaQuery.paddingOf(context).bottom;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AlistenSpacing.page,
            AlistenSpacing.xs,
            AlistenSpacing.page,
            AlistenSpacing.md,
          ),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _SortMenu(count: playlists.length, view: view),
                  ),
                ),
                const SizedBox(width: AlistenSpacing.xs),
                _ViewToggle(view: view.view),
                if (_importing)
                  const SizedBox.square(
                    dimension: AlistenSizes.minTouchTarget,
                    child: Center(
                      child: BusyIndicator(
                        size: AlistenSizes.iconSm,
                        semanticLabel: '正在导入',
                      ),
                    ),
                  )
                else
                  ActionMenuButton(
                    semanticLabel: '导入',
                    icon: AlistenIcons.downloadSimple,
                    iconSize: AlistenSizes.iconSm,
                    entries: [
                      ActionMenuEntry(
                        icon: AlistenIcons.fileArrowUp,
                        label: '从文件导入',
                        onSelected: () => unawaited(_importFile()),
                      ),
                      ActionMenuEntry(
                        icon: AlistenIcons.link,
                        label: '从链接导入',
                        onSelected: () => unawaited(_importLink()),
                      ),
                    ],
                  ),
                IconCircleButton(
                  icon: AlistenIcons.plusBold,
                  semanticLabel: '新建歌单',
                  style: IconCircleButtonStyle.brand,
                  diameter: AlistenSizes.rowAction,
                  iconSize: AlistenSizes.iconSm,
                  onPressed: () => unawaited(_create()),
                ),
              ],
            ),
          ),
        ),
        if (view.view == PlaylistView.grid)
          _grid(playlists, nowMs)
        else
          SliverList.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return _Row(
                key: ValueKey(playlist.id),
                playlist: playlist,
                subtitle: _subtitle(playlist, nowMs),
                onOpen: () => widget.onOpenPlaylist(playlist.id),
                menu: _menu(playlist),
              );
            },
          ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: bottom + AlistenSpacing.xl),
        ),
      ],
    );
  }

  // 卡片的高度按字号算：正方形封面加两行文字；文字比“⋯”的触摸目标矮时取触摸
  // 目标的高度。卡片不超过最大宽度，手机上两列。
  Widget _grid(List<MyPlaylist> playlists, int nowMs) {
    final scaler = MediaQuery.textScalerOf(context);
    final text =
        AlistenTypography.lineHeight(AlistenTypography.bodyStrong, scaler) +
        AlistenSpacing.xxs / 2 +
        AlistenTypography.lineHeight(AlistenTypography.secondary, scaler);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.page),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final columns = math.max(
            2,
            ((width + _gridGap) / (_maxCardWidth + _gridGap)).ceil(),
          );
          final cell = (width - _gridGap * (columns - 1)) / columns;
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: AlistenSpacing.lg,
              crossAxisSpacing: _gridGap,
              mainAxisExtent:
                  cell +
                  AlistenSpacing.xs +
                  math.max(text, AlistenSizes.minTouchTarget),
            ),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return _Card(
                key: ValueKey(playlist.id),
                playlist: playlist,
                size: cell,
                subtitle: _subtitle(playlist, nowMs),
                onOpen: () => widget.onOpenPlaylist(playlist.id),
                menu: _menu(playlist),
              );
            },
          );
        },
      ),
    );
  }

  static String _subtitle(MyPlaylist playlist, int nowMs) =>
      '${playlist.trackCount} 首 · '
      '${formatPlaylistDate(playlist.updatedAtMs, nowMs)}';

  // “我喜欢”不能改名或删除，没有菜单。
  Widget? _menu(MyPlaylist playlist) {
    if (playlist.favorites) return null;
    return ActionMenuButton(
      semanticLabel: '“${playlist.name}”的更多操作',
      iconSize: AlistenSizes.iconSm,
      entries: [
        ActionMenuEntry(
          icon: AlistenIcons.pencilSimple,
          label: '重命名',
          onSelected: () => unawaited(_rename(playlist)),
        ),
        ActionMenuEntry(
          icon: AlistenIcons.trash,
          label: '删除',
          danger: true,
          onSelected: () => unawaited(_delete(playlist)),
        ),
      ],
    );
  }
}

class _SortMenu extends ConsumerWidget {
  const _SortMenu({required this.count, required this.view});

  final int count;
  final PlaylistViewPreference view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playlistViewProvider.notifier);
    final sort = view.sort;
    final semanticLabel =
        '$count 个歌单，排序方式：${sortKeyLabel(sort.key)}，${sortOrderLabel(sort)}';
    void order(SortOrder order) {
      if (order != sort.order) controller.reverse();
    }

    return ActionMenuButton(
      semanticLabel: semanticLabel,
      entries: [
        for (final key in PlaylistSortKey.values)
          ActionMenuEntry(
            icon: AlistenIcons.sortAscending,
            label: sortKeyLabel(key),
            checked: key == sort.key,
            onSelected: () => controller.setSortKey(key),
          ),
        for (final (direction, icon) in const [
          (SortOrder.descending, AlistenIcons.arrowDown),
          (SortOrder.ascending, AlistenIcons.arrowUpBold),
        ])
          ActionMenuEntry(
            icon: icon,
            label: sortOrderLabel(PlaylistSort(sort.key, direction)),
            checked: direction == sort.order,
            onSelected: () => order(direction),
          ),
      ],
      trigger: (open, toggle) => _SortTrigger(
        count: count,
        sort: sort,
        semanticLabel: semanticLabel,
        open: open,
        onPressed: toggle,
      ),
    );
  }
}

class _SortTrigger extends StatelessWidget {
  const _SortTrigger({
    required this.count,
    required this.sort,
    required this.semanticLabel,
    required this.open,
    required this.onPressed,
  });

  final int count;
  final PlaylistSort sort;
  final String semanticLabel;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final muted = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    return Pressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      expanded: open,
      focusRadius: BorderRadius.circular(AlistenRadii.sm),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AlistenSizes.minTouchTarget,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$count 个歌单 · '),
                  TextSpan(
                    text: sortKeyLabel(sort.key),
                    style: AlistenTypography.weighted(
                      AlistenTypography.secondary,
                      FontWeight.w600,
                    ).copyWith(color: colors.onGlass),
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AlistenSpacing.xxs / 2,
                      ),
                      child: Icon(
                        sort.order == SortOrder.ascending
                            ? AlistenIcons.arrowUpBold
                            : AlistenIcons.arrowDown,
                        size: MediaQuery.textScalerOf(context)
                            .scale(AlistenSizes.inlineIcon),
                        color: colors.onGlass,
                      ),
                    ),
                  ),
                ],
              ),
              style: muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewToggle extends ConsumerWidget {
  const _ViewToggle({required this.view});

  final PlaylistView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grid = view == PlaylistView.grid;
    return IconCircleButton(
      icon: grid ? AlistenIcons.rows : AlistenIcons.squaresFour,
      semanticLabel: grid ? '以列表显示' : '以网格显示',
      style: IconCircleButtonStyle.plain,
      iconSize: AlistenSizes.iconSm,
      onPressed: () => ref
          .read(playlistViewProvider.notifier)
          .setView(grid ? PlaylistView.list : PlaylistView.grid),
    );
  }
}

// 整张卡片是一个按钮，“⋯”叠在它的文字一侧，读屏分开读两者。
class _Card extends StatelessWidget {
  const _Card({
    required this.playlist,
    required this.size,
    required this.subtitle,
    required this.onOpen,
    required this.menu,
    super.key,
  });

  final MyPlaylist playlist;
  final double size;
  final String subtitle;
  final VoidCallback onOpen;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final menu = this.menu;
    return Stack(
      children: [
        Pressable(
          onPressed: onOpen,
          semanticLabel: '${playlist.name}，$subtitle',
          focusRadius: BorderRadius.circular(AlistenRadii.md),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlaylistCover(
                  url: playlist.coverUrl,
                  favorites: playlist.favorites,
                  size: size,
                  radius: AlistenRadii.md,
                ),
                const SizedBox(height: AlistenSpacing.xs),
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: menu == null ? 0 : AlistenSizes.minTouchTarget,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PlaylistName(
                        name: playlist.name,
                        favorites: playlist.favorites,
                        style: AlistenTypography.bodyStrong.copyWith(
                          color: colors.onGlass,
                        ),
                      ),
                      const SizedBox(height: AlistenSpacing.xxs / 2),
                      Text(
                        subtitle,
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
            ),
          ),
        ),
        if (menu != null) PositionedDirectional(end: 0, bottom: 0, child: menu),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.playlist,
    required this.subtitle,
    required this.onOpen,
    required this.menu,
    super.key,
  });

  final MyPlaylist playlist;
  final String subtitle;
  final VoidCallback onOpen;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final menu = this.menu;
    return Stack(
      children: [
        Pressable(
          onPressed: onOpen,
          semanticLabel: '${playlist.name}，$subtitle',
          focusRadius: BorderRadius.circular(AlistenRadii.md),
          child: ExcludeSemantics(
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                AlistenSpacing.page,
                AlistenSpacing.xs,
                AlistenSpacing.page +
                    (menu == null ? 0 : AlistenSizes.minTouchTarget),
                AlistenSpacing.xs,
              ),
              child: Row(
                children: [
                  PlaylistCover(
                    url: playlist.coverUrl,
                    favorites: playlist.favorites,
                    size: AlistenSizes.rowCover,
                  ),
                  const SizedBox(width: AlistenSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PlaylistName(
                          name: playlist.name,
                          favorites: playlist.favorites,
                          style: AlistenTypography.bodyStrong.copyWith(
                            color: colors.onGlass,
                          ),
                        ),
                        Text(
                          subtitle,
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
              ),
            ),
          ),
        ),
        if (menu != null)
          PositionedDirectional(
            end: AlistenSpacing.xs,
            top: 0,
            bottom: 0,
            child: Center(child: menu),
          ),
      ],
    );
  }
}
