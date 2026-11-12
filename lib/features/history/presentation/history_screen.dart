import 'dart:async';

import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/history/application/history_controller.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _unknownText = '结果未知，已重新读取播放历史。';

const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

// 每次渲染的日期组数。视口会布局全部 sliver，屏幕外的日期组仍要构建标题和
// 首行并加载封面，所以只渲染一个窗口，接近末尾时再放宽。
const _dayBatch = 8;

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({
    required this.onResult,
    required this.onNotice,
    required this.onCopyTitle,
    this.saveToPlaylist,
    super.key,
  });

  final QueueResultCallback onResult;

  /// 删除和清空的结果可能在页面关闭之后才提示。
  final void Function(ToastKind kind, String text) onNotice;
  final ValueChanged<String> onCopyTitle;

  /// 保存到歌单属于歌单功能，由 app 层组装传入；为 null 时菜单里没有这一项。
  final void Function(BuildContext context, Track track, String title)?
  saveToPlaylist;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final TextEditingController _filter;
  final _filterFocus = FocusNode(debugLabel: 'history filter');
  late final AppLifecycleListener _lifecycle;
  final _scroll = ScrollController();

  // 正在删除的曲目键，值表示是否由左滑发起。左滑发起时，Dismissible 在等待
  // confirmDismiss 期间自己会拦住新的拖动；把它改成不可滑动会让滑开的行丢掉
  // 红色背景，所以只关掉读屏发起的那一行的左滑。
  final _deleting = <String, bool>{};
  void Function()? _close;
  bool _exporting = false;
  int _dayWindow = _dayBatch;

  HistoryController get _history =>
      ref.read(historyControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _filter = TextEditingController(
      text: ref.read(historyControllerProvider).query,
    );
    _lifecycle = AppLifecycleListener(onHide: _releaseFocus);
    // 读取会修改 provider 状态，不能在构建期间开始。
    unawaited(
      Future.microtask(() {
        if (mounted) _close = _history.open();
      }),
    );
  }

  @override
  void dispose() {
    _close?.call();
    _lifecycle.dispose();
    _filterFocus.dispose();
    _filter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // 面板关闭时框架会把焦点还给最后聚焦的输入框，从系统分享或后台回来时仍有
  // 焦点的输入框会再次弹出键盘，所以打开面板、分享和进入后台之前先放下焦点。
  void _releaseFocus() => _filterFocus.unfocus();

  void _pick(Track track, String title) {
    unawaited(pickSong(ref, widget.onResult, track, title));
  }

  void Function(Track track, String title)? get _save {
    final save = widget.saveToPlaylist;
    if (save == null) return null;
    return (track, title) {
      _releaseFocus();
      save(context, track, title);
    };
  }

  void _filterBy(String query) {
    _history.filter(query);
    setState(() => _dayWindow = _dayBatch);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _clearFilter() {
    _filter.clear();
    _filterBy('');
  }

  bool _onScroll(int depth, ScrollMetrics metrics, int days) {
    if (depth == 0 &&
        metrics.extentAfter < metrics.viewportDimension &&
        _dayWindow < days) {
      setState(() => _dayWindow += _dayBatch);
    }
    return false;
  }

  // 控制器和回调先取出：结果可能在页面关闭之后才返回。
  Future<bool> _delete(Listen listen, {required bool swiped}) async {
    final key = trackKey(listen.track);
    if (_deleting.containsKey(key)) return false;
    final history = _history;
    final notice = widget.onNotice;
    setState(() => _deleting[key] = swiped);
    final result = await history.remove(listen);
    if (mounted) setState(() => _deleting.remove(key));
    _report(notice, result, success: '已删除播放记录');
    return result is MutationSucceeded<void>;
  }

  static void _report(
    void Function(ToastKind kind, String text) notice,
    MutationResult<void> result, {
    String? success,
  }) {
    switch (result) {
      case MutationSucceeded():
        if (success != null) notice(ToastKind.success, success);
      case MutationFailed(:final message) || MutationNotSent(:final message):
        notice(ToastKind.failure, message);
      case MutationUnknown():
        notice(ToastKind.warning, _unknownText);
    }
  }

  Future<void> _export() async {
    _releaseFocus();
    setState(() => _exporting = true);
    try {
      await _history.exportHistory();
    } on Object {
      if (mounted) widget.onNotice(ToastKind.failure, '导出失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // 请求期间面板保持打开；用户中途取消时结果照样提示。
  Future<void> _clear() async {
    _releaseFocus();
    final history = _history;
    final notice = widget.onNotice;
    await showConfirmSheet(
      context,
      title: '清空播放历史',
      message: '将清空你的全部播放记录，登录同一个账号的其他设备上也会一起清空。',
      confirmLabel: '清空',
      confirmIcon: AlistenIcons.broom,
      onConfirm: () async {
        final result = await history.clear();
        _report(notice, result);
        return result is MutationSucceeded<void>;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyControllerProvider);
    final listens = history.listens;
    final empty = listens == null || listens.isEmpty;
    final days = _days(history.filteredListens).toList(growable: false);
    final now = DateTime.fromMillisecondsSinceEpoch(
      ref.read(historyNowProvider)(),
    );
    final headingExtent = _DayHeading.extentOf(context);
    // 已包含悬浮在安全区之上的迷你播放条。
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AlistenScaffold(
      // 提示出现在筛选框下方，不挡住正在输入的内容。
      topBar: ToastClearance(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AlistenTopBar(
              leading: IconCircleButton(
                icon: AlistenIcons.arrowLeft,
                semanticLabel: '返回',
                style: IconCircleButtonStyle.plain,
                onPressed: () => unawaited(Navigator.maybePop(context)),
              ),
              title: '播放历史',
              actions: [
                if (_exporting)
                  const SizedBox.square(
                    dimension: AlistenSizes.minTouchTarget,
                    child: Center(
                      child: BusyIndicator(
                        size: AlistenSizes.iconSm,
                        semanticLabel: '正在导出',
                      ),
                    ),
                  )
                else
                  IconCircleButton(
                    icon: AlistenIcons.export,
                    semanticLabel: '导出播放历史',
                    style: IconCircleButtonStyle.plain,
                    onPressed: empty ? null : () => unawaited(_export()),
                  ),
                IconCircleButton(
                  icon: AlistenIcons.broom,
                  semanticLabel: '清空播放历史',
                  style: IconCircleButtonStyle.plain,
                  onPressed: empty ? null : () => unawaited(_clear()),
                ),
              ],
            ),
            if (!empty || history.query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AlistenSpacing.md,
                  AlistenSpacing.xxs,
                  AlistenSpacing.md,
                  AlistenSpacing.xs,
                ),
                child: AlistenTextField(
                  controller: _filter,
                  focusNode: _filterFocus,
                  hint: '筛选歌名、歌手或专辑',
                  icon: AlistenIcons.magnifyingGlass,
                  pill: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _filterBy,
                  onClear: () => _filterBy(''),
                  onTapOutside: (_) => _releaseFocus(),
                ),
              ),
          ],
        ),
      ),
      body: listens == null
          ? _pending(history.error, bottom)
          // 内容不足一屏时不会滚动，只有尺寸变化通知，两种都要监听才能放宽
          // 窗口。
          : NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) => _onScroll(
                notification.depth,
                notification.metrics,
                days.length,
              ),
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (notification) => _onScroll(
                  notification.depth,
                  notification.metrics,
                  days.length,
                ),
                child: _list(listens, days, now, headingExtent, bottom),
              ),
            ),
    );
  }

  Widget _pending(String? error, double bottom) {
    if (error == null) {
      return const Center(
        child: BusyIndicator(size: AlistenSizes.iconLg, semanticLabel: '加载中'),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Semantics(
        liveRegion: true,
        child: EmptyState(
          icon: AlistenIcons.cloudSlash,
          title: '播放历史没有读出来',
          message: error,
          action: PillButton(
            label: '重试',
            icon: AlistenIcons.arrowClockwise,
            style: PillButtonStyle.secondary,
            onPressed: () => unawaited(_history.load()),
          ),
        ),
      ),
    );
  }

  Widget _list(
    List<Listen> listens,
    List<MapEntry<DateTime, List<Listen>>> days,
    DateTime now,
    double headingExtent,
    double bottom,
  ) {
    return CustomScrollView(
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (listens.isEmpty)
          SliverFillRemaining(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: const EmptyState(
                icon: AlistenIcons.clockCounterClockwise,
                title: '你的音乐足迹，从这里开始',
                message: '你在房间里听过的歌会记在这里。',
              ),
            ),
          )
        else if (days.isEmpty)
          SliverFillRemaining(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: EmptyState(
                icon: AlistenIcons.magnifyingGlassMinus,
                title: '没有找到相关记录',
                message: '换个关键词，再找找看。',
                action: PillButton(
                  label: '清除筛选',
                  style: PillButtonStyle.secondary,
                  onPressed: _clearFilter,
                ),
              ),
            ),
          )
        else ...[
          const SliverToBoxAdapter(
            child: PickUnavailableNotice(
              padding: EdgeInsets.fromLTRB(
                AlistenSpacing.page,
                AlistenSpacing.xs,
                AlistenSpacing.page,
                0,
              ),
              outsideRoom: false,
            ),
          ),
          for (final day in days.take(_dayWindow))
            _day(day.key, day.value, now, headingExtent),
          SliverPadding(
            padding: EdgeInsets.only(bottom: bottom + AlistenSpacing.xl),
          ),
        ],
      ],
    );
  }

  Widget _day(
    DateTime day,
    List<Listen> listens,
    DateTime now,
    double headingExtent,
  ) {
    final indexOf = {
      for (final (index, listen) in listens.indexed)
        trackKey(listen.track): index,
    };
    return SliverMainAxisGroup(
      key: ValueKey(day),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _DayHeading(
            label: _dayLabel(day, now),
            count: listens.length,
            extent: headingExtent,
          ),
        ),
        SliverList.builder(
          itemCount: listens.length,
          // 按曲目找回原来的行：上方进来新歌时，等待删除结果、停在滑开位置的
          // 那一行不会被换成新的行。
          findChildIndexCallback: (key) =>
              key is ValueKey<String> ? indexOf[key.value] : null,
          itemBuilder: (context, index) {
            final listen = listens[index];
            final key = trackKey(listen.track);
            return _PlayRow(
              key: ValueKey(key),
              listen: listen,
              deleting: _deleting.containsKey(key),
              swipeable: _deleting[key] != false,
              onPick: _pick,
              onDelete: ({required bool swiped}) =>
                  _delete(listen, swiped: swiped),
              onCopyTitle: widget.onCopyTitle,
              onSave: _save,
            );
          },
        ),
      ],
    );
  }
}

// 按本地日期分组，组按首次出现的顺序排列。
Iterable<MapEntry<DateTime, List<Listen>>> _days(List<Listen> listens) {
  final days = <DateTime, List<Listen>>{};
  for (final listen in listens) {
    final time = DateTime.fromMillisecondsSinceEpoch(listen.heardAtMs);
    days
        .putIfAbsent(DateTime(time.year, time.month, time.day), () => [])
        .add(listen);
  }
  return days.entries;
}

String _dayLabel(DateTime day, DateTime now) {
  if (day == DateTime(now.year, now.month, now.day)) return '今天';
  if (day == DateTime(now.year, now.month, now.day - 1)) return '昨天';
  final date = day.year == now.year
      ? '${day.month}月${day.day}日'
      : '${day.year}年${day.month}月${day.day}日';
  return '$date ${_weekdays[day.weekday - 1]}';
}

String _subtitle(Listen listen) {
  final meta = listen.meta;
  return [
    meta.artist.isEmpty ? '未知艺术家' : meta.artist,
    ?_sourceLabel(listen.track),
    meta.album,
  ].where((part) => part.isNotEmpty).join(' · ');
}

// 与 Web 的 sourceName 一致，只为哔哩哔哩的歌显示来源。search 的 _sourceName
// 给每个来源都起了名字，不能复用。
String? _sourceLabel(Track track) =>
    track.source == TrackSource.bilibili ? '哔哩哔哩' : null;

final class _DayHeading extends SliverPersistentHeaderDelegate {
  _DayHeading({required this.label, required this.count, required this.extent});

  final String label;
  final int count;
  final double extent;

  // 吸顶标题的高度必须固定，所以按系统文字缩放算出一行标题的高度。
  static double extentOf(BuildContext context) {
    final style = AlistenTypography.bodyStrong;
    return (MediaQuery.textScalerOf(context).scale(style.fontSize!) *
                style.height!)
            .ceilToDouble() +
        2 * AlistenSpacing.xs;
  }

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = AlistenColors.of(context);
    return SizedBox.expand(
      child: ColoredBox(
        // 在 `SliverMainAxisGroup` 的首个子项中 `overlapsContent` 几乎总是
        // false；吸顶之后 `shrinkOffset` 才大于 0，下方的行开始从标题下滚过。
        color: overlapsContent || shrinkOffset > 0
            ? colors.floor
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.page),
          child: Semantics(
            header: true,
            container: true,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AlistenTypography.weighted(
                      AlistenTypography.bodyStrong,
                      FontWeight.w700,
                    ).copyWith(color: colors.onGlass),
                  ),
                ),
                const SizedBox(width: AlistenSpacing.xs),
                Text(
                  '$count 首',
                  maxLines: 1,
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlassMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_DayHeading oldDelegate) =>
      oldDelegate.label != label ||
      oldDelegate.count != count ||
      oldDelegate.extent != extent;
}

// 左滑删除对读屏不可用，所以同时提供“删除”自定义动作。
class _PlayRow extends StatelessWidget {
  const _PlayRow({
    required this.listen,
    required this.deleting,
    required this.swipeable,
    required this.onPick,
    required this.onDelete,
    required this.onCopyTitle,
    required this.onSave,
    super.key,
  });

  final Listen listen;

  /// 删除还没有结果：不再提供“删除”动作。
  final bool deleting;
  final bool swipeable;
  final PickSong onPick;

  /// 服务端确认删除时返回 true。
  final Future<bool> Function({required bool swiped}) onDelete;
  final ValueChanged<String> onCopyTitle;
  final void Function(Track track, String title)? onSave;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final meta = listen.meta;
    final save = onSave;
    return Dismissible(
      key: ValueKey(trackKey(listen.track)),
      direction: swipeable
          ? DismissDirection.endToStart
          : DismissDirection.none,
      movementDuration: AlistenDurations.of(context, AlistenDurations.short),
      resizeDuration: AlistenDurations.of(context, AlistenDurations.short),
      // 等服务端确认再收起：成功时这一行已随列表重建离开，失败时滑回原处。
      confirmDismiss: (_) => onDelete(swiped: true),
      background: ColoredBox(
        color: colors.danger.withValues(alpha: AlistenTint.fill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.page),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(
                AlistenIcons.trashFill,
                size: AlistenSizes.iconSm,
                color: colors.danger,
              ),
              const SizedBox(width: AlistenSpacing.xxs),
              Text(
                '删除',
                style: AlistenTypography.weighted(
                  AlistenTypography.secondary,
                  FontWeight.w700,
                ).copyWith(color: colors.danger),
              ),
            ],
          ),
        ),
      ),
      child: TrackRow(
        title: meta.title,
        subtitle: _subtitle(listen),
        coverUrl: meta.coverUrl,
        onLongPress: () => onCopyTitle(meta.title),
        longPressHint: copyTitleHint,
        semanticActions: deleting
            ? null
            : {
                const CustomSemanticsAction(label: '删除'): () =>
                    unawaited(onDelete(swiped: false)),
              },
        padding: const EdgeInsets.fromLTRB(
          AlistenSpacing.page,
          AlistenSpacing.xxs,
          AlistenSpacing.xs,
          AlistenSpacing.xxs,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 点歌结果写成文字，与“⋯”并排时，320 dp 宽的屏幕在 2 倍以上字号下会
            // 撑破整行；结果另作为按钮的值读出，所以限制缩放。
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 2,
              child: PickControl(
                track: listen.track,
                title: meta.title,
                label: '再点一次《${meta.title}》',
                tone: PickTone.quiet,
                hideOutsideRoom: true,
                onPick: onPick,
              ),
            ),
            ActionMenuButton(
              semanticLabel: '《${meta.title}》的更多操作',
              iconSize: AlistenSizes.iconSm,
              entries: [
                if (save != null)
                  ActionMenuEntry(
                    icon: AlistenIcons.listPlus,
                    label: '保存到歌单',
                    onSelected: () => save(listen.track, meta.title),
                  ),
                ActionMenuEntry(
                  icon: AlistenIcons.copy,
                  label: copyTitleHint,
                  onSelected: () => onCopyTitle(meta.title),
                ),
                ActionMenuEntry(
                  icon: AlistenIcons.trash,
                  label: '删除',
                  danger: true,
                  enabled: !deleting,
                  onSelected: () => unawaited(onDelete(swiped: false)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
