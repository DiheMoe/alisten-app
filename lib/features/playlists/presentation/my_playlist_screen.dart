import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/playlist/playlist_date.dart';
import 'package:alisten/domain/playlist/track_order.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/application/my_playlist_controller.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/presentation/playlist_header.dart';
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/features/playlists/presentation/playlist_name_form.dart';
import 'package:alisten/features/playlists/presentation/playlist_song.dart';
import 'package:alisten/features/playlists/presentation/playlist_states.dart';
import 'package:alisten/features/playlists/presentation/save_to_playlist_sheet.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MyPlaylistScreen extends ConsumerStatefulWidget {
  const MyPlaylistScreen({
    required this.id,
    required this.onResult,
    required this.onNotice,
    required this.onCopyTitle,
    required this.onOpenAccount,
    required this.onDeleted,
    super.key,
  });

  final String id;

  /// 点歌结果和提示都要在比页面存活更久的地方报告。
  final QueueResultCallback onResult;
  final PlaylistNotice onNotice;
  final ValueChanged<String> onCopyTitle;
  final VoidCallback onOpenAccount;

  /// 删除成功或者在“这个歌单不存在了”里返回时回到列表。
  final VoidCallback onDeleted;

  @override
  ConsumerState<MyPlaylistScreen> createState() => _MyPlaylistScreenState();
}

class _MyPlaylistScreenState extends ConsumerState<MyPlaylistScreen> {
  // iPad 上导出的分享弹窗指向“⋯”按钮。
  final _menu = GlobalKey();

  // 自己删除之后列表先去掉了它：离开的转场里页面保持原样，不闪出“不存在了”。
  bool _leaving = false;
  MyPlaylist? _shown;
  bool _sharing = false;

  MyPlaylistController get _detail =>
      ref.read(myPlaylistControllerProvider(widget.id).notifier);

  MyPlaylistsController get _playlists =>
      ref.read(myPlaylistsControllerProvider.notifier);

  static MyPlaylist? _find(List<MyPlaylist>? playlists, String id) {
    for (final playlist in playlists ?? const <MyPlaylist>[]) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  void _pick(Track track, String title) {
    unawaited(pickSong(ref, widget.onResult, track, title));
  }

  void _save(SaveTarget target) {
    unawaited(
      showSaveToPlaylistSheet(
        context,
        target,
        onOpenAccount: widget.onOpenAccount,
        onNotice: widget.onNotice,
      ),
    );
  }

  Future<void> _edit(Future<MutationResult<void>?> edit) async {
    final notice = widget.onNotice;
    final result = await edit;
    if (result != null) reportPlaylistResult(notice, result);
  }

  void _drag(List<TrackSummary> items, int from, int to) {
    final keys = [for (final item in items) trackKey(item.track)];
    final plan = moveTo(keys, {keys[from]}, to);
    if (plan != null) unawaited(_edit(_detail.move(plan)));
  }

  void _moveSelected(List<TrackSummary> items, {required bool top}) {
    final selected = ref.read(myPlaylistControllerProvider(widget.id)).selected;
    final keys = [for (final item in items) trackKey(item.track)];
    final rest = keys.where((key) => !selected.contains(key)).length;
    final plan = moveTo(keys, selected, top ? 0 : rest);
    if (plan != null) unawaited(_edit(_detail.move(plan)));
  }

  Future<void> _removeSelected(List<Track> tracks) {
    final detail = _detail;
    return holdingWhile(
      context,
      myPlaylistControllerProvider(widget.id),
      () async {
        if (tracks.length > 1) {
          final confirmed = await showConfirmSheet(
            context,
            title: '移出歌曲',
            message: '把 ${tracks.length} 首歌移出这个歌单？',
            confirmLabel: '移出',
            confirmIcon: AlistenIcons.minusCircle,
          );
          if (!confirmed) return;
        }
        await _edit(detail.remove(tracks));
      },
    );
  }

  void _rename(MyPlaylist playlist) {
    final playlists = _playlists;
    unawaited(
      showPlaylistNameSheet<void>(
        context,
        title: '重命名',
        initialName: playlist.name,
        confirmLabel: '保存',
        busyLabel: '保存',
        cancellable: false,
        onSubmit: (name) => playlists.rename(playlist, name),
      ),
    );
  }

  // 回复之前不再发第二个：分享和重新生成每次都换掉链接，连点会让刚复制的
  // 链接失效。
  Future<void> _whileSharing(Future<void> Function() action) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await holdingWhile(context, myPlaylistsControllerProvider, action);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // 只复制到剪贴板，不弹出系统分享面板：与 Web 和房间邀请链接一致。
  Future<void> _share(MyPlaylist playlist, {required bool again}) {
    final playlists = _playlists;
    final notice = widget.onNotice;
    return _whileSharing(() async {
      if (again) {
        final confirmed = await showConfirmSheet(
          context,
          title: '重新生成分享链接',
          message: '生成新链接之后，之前分享出去的链接就打不开了。',
          confirmLabel: '重新生成',
          confirmIcon: AlistenIcons.repeat,
        );
        if (!confirmed) return;
      }
      final result = await playlists.share(playlist);
      if (result case MutationSucceeded(:final value)) {
        unawaited(
          Clipboard.setData(ClipboardData(text: playlists.shareLink(value))),
        );
      }
      reportPlaylistResult(
        notice,
        result,
        success: again ? '已生成新链接并复制' : '已开启分享，链接已复制',
      );
    });
  }

  void _copyLink(String shareId) {
    unawaited(
      Clipboard.setData(ClipboardData(text: _playlists.shareLink(shareId))),
    );
    widget.onNotice(ToastKind.success, '已复制分享链接');
  }

  Future<void> _unshare(MyPlaylist playlist) {
    final playlists = _playlists;
    final notice = widget.onNotice;
    return _whileSharing(() async {
      final confirmed = await showConfirmSheet(
        context,
        title: '停止分享',
        message: '停止之后，分享出去的链接就打不开了。',
        confirmLabel: '停止分享',
        confirmIcon: AlistenIcons.linkBreak,
      );
      if (!confirmed) return;
      reportPlaylistResult(
        notice,
        await playlists.unshare(playlist),
        success: '已停止分享',
      );
    });
  }

  Future<void> _export() async {
    final box = _menu.currentContext?.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await _edit(_detail.export(origin));
  }

  Future<void> _delete(MyPlaylist playlist) {
    final playlists = _playlists;
    final notice = widget.onNotice;
    return holdingWhile(context, myPlaylistsControllerProvider, () async {
      if (!await confirmPlaylistDelete(context, playlist)) return;
      final result = await playlists.delete(playlist);
      if (result is! MutationSucceeded) {
        reportPlaylistResult(notice, result);
      } else if (mounted) {
        _leaving = true;
        widget.onDeleted();
      }
    });
  }

  List<ActionMenuEntry> _actions(MyPlaylist playlist, bool exporting) {
    final shareId = playlist.shareId;
    return [
      if (!playlist.favorites)
        ActionMenuEntry(
          icon: AlistenIcons.pencilSimple,
          label: '重命名',
          onSelected: () => _rename(playlist),
        ),
      if (shareId == null)
        ActionMenuEntry(
          icon: AlistenIcons.shareNetwork,
          label: '分享',
          enabled: !_sharing,
          onSelected: () => unawaited(_share(playlist, again: false)),
        )
      else ...[
        ActionMenuEntry(
          icon: AlistenIcons.link,
          label: '复制分享链接',
          enabled: !_sharing,
          onSelected: () => _copyLink(shareId),
        ),
        ActionMenuEntry(
          icon: AlistenIcons.repeat,
          label: '重新生成分享链接',
          enabled: !_sharing,
          onSelected: () => unawaited(_share(playlist, again: true)),
        ),
        ActionMenuEntry(
          icon: AlistenIcons.linkBreak,
          label: '停止分享',
          enabled: !_sharing,
          onSelected: () => unawaited(_unshare(playlist)),
        ),
      ],
      ActionMenuEntry(
        icon: AlistenIcons.export,
        label: '导出',
        enabled: !exporting,
        onSelected: () => unawaited(_export()),
      ),
      if (!playlist.favorites)
        ActionMenuEntry(
          icon: AlistenIcons.trash,
          label: '删除',
          danger: true,
          onSelected: () => unawaited(_delete(playlist)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(myPlaylistsControllerProvider);
    final detail = ref.watch(myPlaylistControllerProvider(widget.id));
    final found = _find(list.playlists, widget.id);
    if (found != null) _shown = found;
    final playlist = found ?? (_leaving ? _shown : null);
    final gone = detail.gone && !_leaving;
    final items = detail.items ?? const <TrackSummary>[];
    // 歌单不在了、换成游客时，控制器里的选择不再显示，返回也不再被拦下。
    final selecting =
        !list.guest &&
        !gone &&
        playlist != null &&
        detail.selecting &&
        items.isNotEmpty;
    final List<Widget> slivers;
    if (list.guest) {
      slivers = [
        PlaylistPageFill(
          child: PlaylistGuestState(onOpenAccount: widget.onOpenAccount),
        ),
      ];
    } else if (gone) {
      slivers = [
        PlaylistPageFill(
          child: EmptyState(
            icon: AlistenIcons.listDashes,
            title: '这个歌单不存在了',
            action: PillButton(
              label: '返回我的歌单',
              icon: AlistenIcons.arrowLeft,
              style: PillButtonStyle.secondary,
              onPressed: widget.onDeleted,
            ),
          ),
        ),
      ];
    } else if (playlist == null) {
      final error = list.error;
      slivers = [
        PlaylistPageFill(
          child: error == null
              ? const PlaylistLoading()
              : PlaylistReadFailure(
                  message: error,
                  onRetry: () => unawaited(_playlists.retry()),
                ),
        ),
      ];
    } else {
      slivers = [
        SliverToBoxAdapter(
          child: _header(playlist, list.loadedAtMs, detail, selecting),
        ),
        ..._songs(detail, selecting),
      ];
    }
    final selected = [
      for (final item in items)
        if (detail.selected.contains(trackKey(item.track))) item.track,
    ];
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) _detail.stopSelecting();
      },
      child: AlistenScaffold(
        body: Stack(
          children: [
            CustomScrollView(slivers: slivers),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: selecting
                  ? _SelectingBar(
                      count: detail.selected.length,
                      allSelected: detail.selected.length == items.length,
                      onClose: _detail.stopSelecting,
                      onToggleAll: detail.selected.length == items.length
                          ? _detail.clearSelection
                          : _detail.selectAll,
                    )
                  : AlistenTopBar(
                      leading: IconCircleButton(
                        icon: AlistenIcons.arrowLeft,
                        semanticLabel: '返回',
                        onPressed: () => unawaited(Navigator.maybePop(context)),
                      ),
                    ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _SelectionBar(
                visible: selecting,
                enabled: selected.isNotEmpty,
                onSave: () {
                  if (playlist == null) return;
                  _save(SaveManyTracks(from: playlist, tracks: selected));
                },
                onTop: () => _moveSelected(items, top: true),
                onBottom: () => _moveSelected(items, top: false),
                onRemove: () => unawaited(_removeSelected(selected)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(
    MyPlaylist playlist,
    int nowMs,
    MyPlaylistState detail,
    bool selecting,
  ) {
    final items = detail.items;
    final count = items?.length ?? playlist.trackCount;
    return PlaylistHeader(
      coverUrl: playlist.coverUrl,
      favorites: playlist.favorites,
      name: playlist.name,
      facts:
          '$count 首，更新于${formatPlaylistDate(playlist.updatedAtMs, nowMs)}，'
          '创建于${formatPlaylistDate(playlist.createdAtMs, nowMs)}',
      children: [
        const SizedBox(height: AlistenSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AlistenSpacing.xs,
          runSpacing: AlistenSpacing.xs,
          children: [
            if (items != null && items.isNotEmpty && !selecting)
              PillButton(
                label: '选择',
                icon: AlistenIcons.listChecks,
                style: PillButtonStyle.secondary,
                onPressed: _detail.startSelecting,
              ),
            if (detail.exporting)
              const SizedBox.square(
                dimension: AlistenSizes.minTouchTarget,
                child: Center(
                  child: BusyIndicator(
                    size: AlistenSizes.iconSm,
                    semanticLabel: '正在导出',
                  ),
                ),
              ),
            KeyedSubtree(
              key: _menu,
              child: ActionMenuButton(
                semanticLabel: '“${playlist.name}”的更多操作',
                entries: _actions(playlist, detail.exporting),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _songs(MyPlaylistState detail, bool selecting) {
    final items = detail.items;
    final error = detail.error;
    final bottom = MediaQuery.paddingOf(context).bottom;
    if (items == null || items.isEmpty) {
      return [
        SliverFillRemaining(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: items != null
                // 文字改用 App 里这两处的叫法，Web 写的是“播放栏、播放列表”。
                ? const EmptyState(
                    icon: AlistenIcons.queue,
                    title: '这个歌单还是空的',
                    message: '在播放器、队列和播放历史里，可以把歌保存到歌单。',
                  )
                : error == null
                ? const PlaylistLoading()
                : PlaylistReadFailure(
                    message: error,
                    onRetry: () => unawaited(_detail.load()),
                  ),
          ),
        ),
      ];
    }
    final colors = AlistenColors.of(context);
    return [
      const SliverToBoxAdapter(child: PickUnavailableNotice()),
      // 读屏的“移到开头”“上移”“下移”“移到末尾”由它加在每一项上，中文取自
      // WidgetsLocalizations。拖动只从选择时出现的把手开始：平时一行只留点歌和
      // “⋯”，长按留给复制歌名。
      SliverReorderableList(
        itemCount: items.length,
        onReorderItem: (from, to) => _drag(items, from, to),
        proxyDecorator: (child, _, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: colors.raised,
            borderRadius: BorderRadius.circular(AlistenRadii.md),
            border: Border.all(color: colors.glassStroke),
          ),
          child: child,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          final key = trackKey(item.track);
          if (selecting) {
            return _SelectableSong(
              key: ValueKey(key),
              item: item,
              index: index,
              selected: detail.selected.contains(key),
              onToggle: () => _detail.toggle(key),
            );
          }
          return _Song(
            key: ValueKey(key),
            item: item,
            onPick: _pick,
            onCopyTitle: widget.onCopyTitle,
            onSave: () =>
                _save(SaveOneTrack(track: item.track, title: item.meta.title)),
            onRemove: () => unawaited(_edit(_detail.remove([item.track]))),
          );
        },
      ),
      SliverPadding(
        padding: EdgeInsets.only(
          bottom:
              bottom +
              AlistenSpacing.xl +
              (selecting ? _SelectionBar.heightOf(context) : 0),
        ),
      ),
    ];
  }
}

// 一行只留点歌一个主操作，保存和移出收进“⋯”，歌名才不被挤短。
class _Song extends StatelessWidget {
  const _Song({
    required this.item,
    required this.onPick,
    required this.onCopyTitle,
    required this.onSave,
    required this.onRemove,
    super.key,
  });

  final TrackSummary item;
  final PickSong onPick;
  final ValueChanged<String> onCopyTitle;
  final VoidCallback onSave;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final meta = item.meta;
    final subtitle = playlistSongSubtitle(meta);
    void copy() => onCopyTitle(meta.title);
    // 列表的移动操作加在包住这一项的节点上：歌名和“复制歌名”并进同一个节点，
    // 读屏在这首歌上就能找到它们，而不是停在一个没有名字的外层节点上。
    return Semantics(
      label: subtitle == null ? meta.title : '${meta.title}\n$subtitle',
      onLongPress: copy,
      onLongPressHint: copyTitleHint,
      child: Row(
        children: [
          Expanded(
            child: ExcludeSemantics(
              child: TrackRow(
                title: meta.title,
                subtitle: subtitle,
                coverUrl: meta.coverUrl,
                onLongPress: copy,
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AlistenSpacing.page,
                  AlistenSpacing.xxs,
                  0,
                  AlistenSpacing.xxs,
                ),
              ),
            ),
          ),
          const SizedBox(width: AlistenSpacing.xs),
          // 写出点歌结果的按钮要一百多 dp，320 dp 宽、字号更大时歌名会被挤得只剩
          // 一两个字。结果另作为按钮的值读出。
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: PlaylistPickControl(
              track: item.track,
              title: meta.title,
              onPick: onPick,
            ),
          ),
          ActionMenuButton(
            semanticLabel: '《${meta.title}》的更多操作',
            iconSize: AlistenSizes.iconSm,
            entries: [
              ActionMenuEntry(
                icon: AlistenIcons.listPlus,
                label: '保存到歌单',
                onSelected: onSave,
              ),
              ActionMenuEntry(
                icon: AlistenIcons.copy,
                label: copyTitleHint,
                onSelected: copy,
              ),
              // 单首移出不确认，与 Web 相同。
              ActionMenuEntry(
                icon: AlistenIcons.minusCircle,
                label: '移出这个歌单',
                danger: true,
                onSelected: onRemove,
              ),
            ],
          ),
          const SizedBox(width: AlistenSpacing.xxs),
        ],
      ),
    );
  }
}

// 与 [_Song] 一样，歌名和勾选状态并进列表加了移动操作的那个节点。
class _SelectableSong extends StatelessWidget {
  const _SelectableSong({
    required this.item,
    required this.index,
    required this.selected,
    required this.onToggle,
    super.key,
  });

  final TrackSummary item;
  final int index;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final meta = item.meta;
    final subtitle = playlistSongSubtitle(meta);
    return Semantics(
      label: meta.title,
      checked: selected,
      onTap: onToggle,
      child: ExcludeSemantics(
        child: Pressable(
          onPressed: onToggle,
          button: false,
          child: TrackRow(
            title: meta.title,
            subtitle: subtitle,
            coverUrl: meta.coverUrl,
            padding: const EdgeInsetsDirectional.fromSTEB(
              AlistenSpacing.page,
              AlistenSpacing.xs,
              AlistenSpacing.xxs,
              AlistenSpacing.xs,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: AlistenSizes.minTouchTarget,
                  child: Icon(
                    selected
                        ? AlistenIcons.checkCircleFill
                        : AlistenIcons.circle,
                    color: selected ? colors.success : colors.onGlassMuted,
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: SizedBox.square(
                    dimension: AlistenSizes.minTouchTarget,
                    child: Icon(
                      AlistenIcons.equalsBold,
                      size: AlistenSizes.iconSm,
                      color: colors.onGlassMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectingBar extends StatelessWidget {
  const _SelectingBar({
    required this.count,
    required this.allSelected,
    required this.onClose,
    required this.onToggleAll,
  });

  final int count;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return ToastClearance(
      // 列表在顶栏下面滚过，选中数要始终看得清。
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlistenSpacing.xs,
              vertical: AlistenSpacing.xxs,
            ),
            child: Row(
              children: [
                IconCircleButton(
                  icon: AlistenIcons.x,
                  semanticLabel: '退出选择',
                  style: IconCircleButtonStyle.plain,
                  onPressed: onClose,
                ),
                const SizedBox(width: AlistenSpacing.xxs),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    header: true,
                    child: Text(
                      '已选 $count 首',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AlistenTypography.weighted(
                        AlistenTypography.bodyStrong,
                        FontWeight.w700,
                      ).copyWith(color: colors.onGlass),
                    ),
                  ),
                ),
                PillButton(
                  label: allSelected ? '取消全选' : '全选',
                  style: PillButtonStyle.ghost,
                  onPressed: onToggleAll,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 开始收起时就不再接收点按，也不被读屏读出：收起途中的按钮还看得见，不能
/// 再对已经退出的选择生效。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.visible,
    required this.enabled,
    required this.onSave,
    required this.onTop,
    required this.onBottom,
    required this.onRemove,
  });

  final bool visible;
  final bool enabled;
  final VoidCallback onSave;
  final VoidCallback onTop;
  final VoidCallback onBottom;
  final VoidCallback onRemove;

  static double heightOf(BuildContext context) {
    final label = AlistenTypography.lineHeight(
      AlistenTypography.secondary,
      MediaQuery.textScalerOf(context),
    );
    final button = math.max(
      AlistenSizes.minTouchTarget,
      AlistenSizes.iconSm + AlistenSpacing.xxs + label + 2 * AlistenSpacing.xxs,
    );
    return button + 2 * AlistenSpacing.xs + AlistenSpacing.xs;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final motion = AlistenDurations.of(context, AlistenDurations.short);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1),
          duration: motion,
          curve: AlistenCurves.standard,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: motion,
            curve: AlistenCurves.standard,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AlistenSpacing.sm,
                0,
                AlistenSpacing.sm,
                bottom + AlistenSpacing.xs,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.raised,
                  borderRadius: BorderRadius.circular(AlistenRadii.md),
                  border: Border.all(color: colors.glassStroke),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AlistenSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: _BarButton(
                          icon: AlistenIcons.listPlus,
                          label: '保存到歌单',
                          semanticLabel: '把选中的歌保存到歌单',
                          onPressed: enabled ? onSave : null,
                        ),
                      ),
                      Expanded(
                        child: _BarButton(
                          icon: AlistenIcons.arrowLineUp,
                          label: '移到最前',
                          semanticLabel: '把选中的歌移到最前',
                          onPressed: enabled ? onTop : null,
                        ),
                      ),
                      Expanded(
                        child: _BarButton(
                          icon: AlistenIcons.arrowLineDown,
                          label: '移到最后',
                          semanticLabel: '把选中的歌移到最后',
                          onPressed: enabled ? onBottom : null,
                        ),
                      ),
                      Expanded(
                        child: _BarButton(
                          icon: AlistenIcons.minusCircle,
                          label: '移出',
                          semanticLabel: '把选中的歌移出这个歌单',
                          danger: true,
                          onPressed: enabled ? onRemove : null,
                        ),
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

/// 字号过大放不下文字时只显示图标，读屏名称不受影响。
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final ink = danger ? colors.danger : colors.onGlass;
    final style = AlistenTypography.secondary.copyWith(color: ink);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AlistenSizes.minTouchTarget,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final painter = TextPainter(
                text: TextSpan(text: label, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              final fits =
                  painter.width <=
                  constraints.maxWidth - 2 * AlistenSpacing.xxs;
              painter.dispose();
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AlistenSpacing.xxs,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: AlistenSizes.iconSm, color: ink),
                    if (fits) ...[
                      const SizedBox(height: AlistenSpacing.xxs),
                      Text(label, maxLines: 1, style: style),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
