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
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/features/playlists/presentation/playlist_name_form.dart';
import 'package:alisten/features/playlists/presentation/playlist_states.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/page_glow.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/segmented_pills.dart';
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
      confirmIcon: Icons.add_rounded,
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
      background: const PageGlow(),
      topBar: AlistenTopBar(
        leading: IconCircleButton(
          icon: Icons.arrow_back_rounded,
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
    final colors = AlistenColors.of(context);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${playlists.length} 个歌单',
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlassMuted,
                  ),
                ),
                const SizedBox(height: AlistenSpacing.sm),
                _Controls(view: view),
                const SizedBox(height: AlistenSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AlistenSpacing.xs,
                  runSpacing: AlistenSpacing.xs,
                  children: [
                    ActionMenuButton(
                      semanticLabel: '导入',
                      entries: [
                        ActionMenuEntry(
                          icon: Icons.file_open_rounded,
                          label: '从文件导入',
                          onSelected: () => unawaited(_importFile()),
                        ),
                        ActionMenuEntry(
                          icon: Icons.link_rounded,
                          label: '从链接导入',
                          onSelected: () => unawaited(_importLink()),
                        ),
                      ],
                      trigger: (open, toggle) => PillButton(
                        label: _importing ? '正在导入…' : '导入',
                        icon: Icons.download_rounded,
                        style: PillButtonStyle.secondary,
                        busy: _importing,
                        expanded: open,
                        onPressed: _importing ? null : toggle,
                      ),
                    ),
                    PillButton(
                      label: '新建歌单',
                      icon: Icons.add_rounded,
                      onPressed: () => unawaited(_create()),
                    ),
                  ],
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
          icon: Icons.edit_rounded,
          label: '重命名',
          onSelected: () => unawaited(_rename(playlist)),
        ),
        ActionMenuEntry(
          icon: Icons.delete_outline_rounded,
          label: '删除',
          danger: true,
          onSelected: () => unawaited(_delete(playlist)),
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.view});

  final PlaylistViewPreference view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playlistViewProvider.notifier);
    final sort = view.sort;
    final sortLabel = '排序方式：${sortKeyLabel(sort.key)}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      spacing: AlistenSpacing.xs,
      children: [
        SegmentedPills<PlaylistView>(
          segments: const [
            PillSegment(
              value: PlaylistView.grid,
              label: '网格',
              icon: Icons.grid_view_rounded,
            ),
            PillSegment(
              value: PlaylistView.list,
              label: '列表',
              icon: Icons.view_list_rounded,
            ),
          ],
          selected: view.view,
          onChanged: controller.setView,
          showLabels: false,
        ),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: AlistenSpacing.xs,
            children: [
              Flexible(
                child: ActionMenuButton(
                  semanticLabel: sortLabel,
                  entries: [
                    for (final key in PlaylistSortKey.values)
                      ActionMenuEntry(
                        icon: Icons.sort_rounded,
                        label: sortKeyLabel(key),
                        checked: key == sort.key,
                        onSelected: () => controller.setSortKey(key),
                      ),
                  ],
                  trigger: (open, toggle) => _SortButton(
                    label: sortKeyLabel(sort.key),
                    semanticLabel: sortLabel,
                    open: open,
                    onPressed: toggle,
                  ),
                ),
              ),
              IconCircleButton(
                icon: sort.order == SortOrder.ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                semanticLabel: sortOrderLabel(sort),
                onPressed: controller.reverse,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.label,
    required this.semanticLabel,
    required this.open,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final pill = BorderRadius.circular(AlistenRadii.pill);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      expanded: open,
      focusRadius: pill,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AlistenSizes.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.md),
          decoration: BoxDecoration(
            color: colors.glassFill,
            borderRadius: pill,
            border: Border.all(color: colors.glassStroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sort_rounded,
                size: AlistenSizes.iconSm,
                color: colors.onGlass,
              ),
              const SizedBox(width: AlistenSpacing.xxs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AlistenTypography.bodyStrong.copyWith(
                    color: colors.onGlass,
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
