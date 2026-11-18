import 'dart:async';

import 'package:alisten/features/admin/application/admin_media_controller.dart';
import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/media_link_opener.dart';
import 'package:alisten/features/admin/presentation/media_format.dart';
import 'package:alisten/features/admin/presentation/media_pager.dart';
import 'package:alisten/features/admin/presentation/media_row.dart';
import 'package:alisten/features/admin/presentation/media_selection_bar.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/fade_leaving_inert.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pull_refresh.dart';
import 'package:alisten/shared/ui/select_menu.dart';
import 'package:alisten/shared/ui/settings_list.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _skeletonRows = 6;
const _refreshAction = CustomSemanticsAction(label: '刷新');

/// 存储在服务端的歌曲：搜索、排序、每页 20 首翻页，长按多选后批量删除。
class AdminMediaScreen extends ConsumerStatefulWidget {
  const AdminMediaScreen({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<AdminMediaScreen> createState() => _AdminMediaScreenState();
}

class _AdminMediaScreenState extends ConsumerState<AdminMediaScreen> {
  final _search = TextEditingController();

  // 最后交给控制器的搜索词：只移动光标、选中文字时不再查一次。
  String _sent = '';

  // 操作条实际的高度，布局后才知道；列表末尾按它留出空间。
  double _barHeight = 0;

  AdminMediaController get _media =>
      ref.read(adminMediaControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
    unawaited(
      Future.microtask(() {
        if (mounted) unawaited(_media.load());
      }),
    );
  }

  @override
  void dispose() {
    _search
      ..removeListener(_searchChanged)
      ..dispose();
    super.dispose();
  }

  // 输入法还在组字时不查，选定之后再查；停手 0.3 秒由控制器计时。
  void _searchChanged() {
    final value = _search.value;
    if (value.composing.isValid || value.text == _sent) return;
    _sent = value.text;
    _media.setQuery(value.text);
  }

  void _clearSearch() {
    _sent = '';
    _search.clear();
    unawaited(_media.clearQuery());
  }

  Future<void> _openLink(StoredTrack track) async {
    final opened = await ref.read(mediaLinkOpenerProvider).open(track.link);
    if (!opened && mounted) widget.onNotice(ToastKind.failure, '没能打开链接');
  }

  Future<void> _remove(List<StoredTrack> tracks) async {
    final media = _media;
    if (ref.read(adminMediaControllerProvider).removing) return;
    final bytes = tracks.fold(0, (sum, track) => sum + track.bytes);
    final confirmed = await showConfirmSheet(
      context,
      title: '删除 ${tracks.length} 首歌曲？',
      message: '将释放 ${formatBytes(bytes)}，删除后不能恢复。',
      confirmLabel: '删除',
      confirmIcon: AlistenIcons.trash,
      danger: true,
    );
    if (!confirmed || !mounted) return;
    if (ref.read(adminMediaControllerProvider).removing) return;
    final outcome = await media.remove(tracks);
    // 会话已结束时本页会换成令牌页，由那里说明原因。
    if (!mounted || !ref.read(adminSessionProvider).active) return;
    final (kind, text) = switch (outcome) {
      // 一首也没删掉时不说“已删除 0 首”：要么别处已经删了，要么都在播放。
      MediaRemoved(deleted: 0, inUse: 0) => (
        ToastKind.info,
        tracks.length == 1 ? '这首歌已经不在了' : '这些歌曲已经不在了',
      ),
      MediaRemoved(deleted: 0, inUse: final u) => (
        ToastKind.info,
        '$u 首正在房间里播放，没有删除',
      ),
      MediaRemoved(deleted: final d, inUse: 0) => (
        ToastKind.success,
        '已删除 $d 首',
      ),
      MediaRemoved(deleted: final d, inUse: final u) => (
        ToastKind.info,
        '已删除 $d 首；$u 首正在房间里播放，没有删除',
      ),
      MediaRemovalFailed(message: final m, deleted: 0) => (
        ToastKind.failure,
        m,
      ),
      MediaRemovalFailed(message: final m, deleted: final d) => (
        ToastKind.failure,
        '已删除 $d 首；$m',
      ),
      MediaRemovalUnknown() => (ToastKind.warning, '没能确认是否删除，已重新读取'),
      MediaRemovalNotSent(:final message) => (ToastKind.failure, message),
    };
    widget.onNotice(kind, text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminMediaControllerProvider);
    final now = ref.read(adminNowProvider)();
    final bottom = MediaQuery.paddingOf(context).bottom;
    final barSpace = state.selecting ? _barHeight + AlistenSpacing.md : 0.0;
    return PopScope(
      // 返回先退出多选，再按一次才离开页面。
      canPop: !state.selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _media.clearSelection();
      },
      child: AlistenScaffold(
        topBar: AlistenTopBar(
          leading: IconCircleButton(
            icon: AlistenIcons.arrowLeft,
            semanticLabel: '返回',
            style: IconCircleButtonStyle.plain,
            onPressed: () => unawaited(Navigator.maybePop(context)),
          ),
          title: '媒体',
        ),
        body: Stack(
          children: [
            CustomScrollView(
              physics: pullRefreshPhysics(context),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPullRefresh(onRefresh: _media.refresh),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AlistenSpacing.page,
                    0,
                    AlistenSpacing.page,
                    bottom + AlistenSpacing.xl + barSpace,
                  ),
                  sliver: SliverList.list(
                    children: [_header(state), ..._list(state, now)],
                  ),
                ),
              ],
            ),
            Positioned(
              left: AlistenSpacing.page,
              right: AlistenSpacing.page,
              bottom: bottom + AlistenSpacing.md,
              child: _selectionBar(state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AdminMediaState state) {
    final colors = AlistenColors.of(context);
    final total = state.total;
    return Padding(
      padding: const EdgeInsets.only(top: AlistenSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AlistenTextField(
            controller: _search,
            pill: true,
            icon: AlistenIcons.magnifyingGlass,
            hint: '搜索歌名',
            maxLength: 100,
            textInputAction: TextInputAction.search,
            // 输入框已清空，监听里已记下空的搜索词；这里立即生效，不等 0.3 秒。
            onClear: () => unawaited(_media.clearQuery()),
          ),
          const SizedBox(height: AlistenSpacing.xs),
          Row(
            children: [
              const SizedBox(width: AlistenSpacing.xxs),
              Expanded(
                child: total == null
                    ? const SizedBox.shrink()
                    // 读屏用户拉不出下拉刷新，在合计上刷新。
                    : Semantics(
                        container: true,
                        customSemanticsActions: {
                          _refreshAction: () => unawaited(_media.refresh()),
                        },
                        child: Text(
                          '共 $total 首 · 占用 ${formatBytes(state.totalBytes ?? 0)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AlistenTypography.secondary.copyWith(
                            color: colors.onGlassMuted,
                          ),
                        ),
                      ),
              ),
              SelectMenuButton<MediaOrder>(
                label: '排序',
                options: const [
                  SelectOption(value: MediaOrder.stored, label: '最近存储'),
                  SelectOption(value: MediaOrder.idle, label: '最久未播放'),
                  SelectOption(value: MediaOrder.size, label: '占用最大'),
                ],
                selected: state.order,
                onChanged: (order) => unawaited(_media.setOrder(order)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _list(AdminMediaState state, DateTime now) {
    final total = state.total;
    final error = state.error;
    Widget retry() => PillButton(
      label: '重试',
      style: PillButtonStyle.ghost,
      onPressed: state.loading ? null : () => unawaited(_media.retry()),
    );
    if (total == null) {
      return [
        if (error != null)
          _failure(error, retry())
        else
          Semantics(
            container: true,
            label: '正在读取存储的歌曲',
            child: SettingsGroup(
              children: [
                for (var i = 0; i < _skeletonRows; i++)
                  const MediaRowSkeleton(),
              ],
            ),
          ),
      ];
    }
    if (total == 0) {
      return [
        if (state.query.isEmpty)
          const EmptyState(icon: AlistenIcons.hardDrives, title: '还没有存储任何歌曲')
        else
          EmptyState(
            icon: AlistenIcons.magnifyingGlass,
            title: '没有找到歌曲',
            action: PillButton(
              label: '清除搜索',
              style: PillButtonStyle.secondary,
              onPressed: _clearSearch,
            ),
          ),
        if (error != null) _failure(error, retry()),
      ];
    }
    return [
      if (state.items.isNotEmpty)
        SettingsGroup(
          children: [
            for (final track in state.items)
              MediaRow(
                key: ValueKey(track.key),
                track: track,
                now: now,
                selecting: state.selecting,
                selected: state.selected.containsKey(track.key),
                onToggle: () => _media.toggle(track),
                onOpenLink: () => unawaited(_openLink(track)),
                onDelete: () => unawaited(_remove([track])),
              ),
          ],
        ),
      // 翻页读取失败时上一页仍在，原因和重试放在分页条上方。
      if (error != null) _failure(error, retry()),
      if (state.pageCount > 1)
        MediaPager(
          page: state.page,
          pageCount: state.pageCount,
          total: total,
          onGo: (page) => unawaited(_media.goTo(page)),
        ),
    ];
  }

  Widget _failure(String error, Widget retry) => Padding(
    padding: const EdgeInsets.only(top: AlistenSpacing.md),
    child: InlineMessage(text: error, action: retry),
  );

  Widget _selectionBar(AdminMediaState state) {
    return AnimatedSwitcher(
      duration: AlistenDurations.of(context, AlistenDurations.short),
      switchInCurve: AlistenCurves.standard,
      switchOutCurve: AlistenCurves.exit,
      // 从底部浮上来；收起途中不再接收点按，也不被读出。
      transitionBuilder: (child, animation) => fadeLeavingInert(
        SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.4),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
        animation,
      ),
      child: state.selecting
          ? MediaSelectionBar(
              key: const ValueKey('selecting'),
              count: state.selected.length,
              bytes: state.selectedBytes,
              pageSelected: state.pageSelected,
              removing: state.removing,
              onCancel: _media.clearSelection,
              onTogglePage: _media.togglePage,
              onDelete: () => unawaited(_remove([...state.selected.values])),
              onHeight: (height) {
                if (mounted && height != _barHeight) {
                  setState(() => _barHeight = height);
                }
              },
            )
          : const SizedBox.shrink(),
    );
  }
}
