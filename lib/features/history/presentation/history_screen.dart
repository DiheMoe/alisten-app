import 'dart:async';

import 'package:alisten/domain/history/play_record.dart';
import 'package:alisten/domain/server/server_origin.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/history/application/history_controller.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/page_glow.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _notSaved = '这次修改没能保存，重新打开 App 后可能还在。';

const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

// 每次渲染的日期组数。视口会布局全部 sliver，屏幕外的日期组仍要构建标题和
// 首行并加载封面，所以只渲染一个窗口，接近末尾时再放宽。
const _dayBatch = 8;

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({
    required this.onResult,
    required this.onDeleted,
    required this.onCleared,
    required this.onNotice,
    super.key,
  });

  final QueueResultCallback onResult;

  /// [undo] 可能在页面关闭之后才被调用。
  final void Function(String message, VoidCallback undo) onDeleted;

  /// 清空后之前的删除已无法撤销，调用方应收回仍在显示的撤销提示。
  final VoidCallback onCleared;

  final ValueChanged<String> onNotice;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final TextEditingController _filter;
  final _filterFocus = FocusNode(debugLabel: 'history filter');
  late final AppLifecycleListener _lifecycle;
  final _scroll = ScrollController();
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
  }

  @override
  void dispose() {
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

  // 撤销可能在页面关闭后才触发，所以先取出控制器和回调，之后不再访问 ref。
  void _delete(PlayRecord record) {
    final history = _history;
    final notice = widget.onNotice;
    _saving(history.delete(record), notice);
    final title = record.meta.title;
    widget.onDeleted(
      title.isEmpty ? '已删除这条记录' : '已删除《$title》',
      () => _saving(history.restore(record), notice),
    );
  }

  // 状态已经更新，写入失败只提示，不回滚界面。
  static void _saving(Future<void> change, ValueChanged<String> notice) {
    unawaited(change.catchError((Object _) => notice(_notSaved)));
  }

  Future<void> _export() async {
    _releaseFocus();
    setState(() => _exporting = true);
    try {
      await _history.exportHistory();
    } on Object {
      if (mounted) widget.onNotice('导出失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _clear() async {
    _releaseFocus();
    final confirmed = await showConfirmSheet(
      context,
      title: '清空播放历史？',
      message: '这台设备上的播放记录会全部删除，无法恢复。',
      confirmLabel: '清空',
      confirmIcon: Icons.delete_sweep_rounded,
    );
    if (!confirmed || !mounted) return;
    _saving(_history.clear(), widget.onNotice);
    widget.onCleared();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyControllerProvider);
    final currentOrigin = ref.watch(
      currentServerProvider.select((server) => server.origin),
    );
    final records = history.filteredRecords;
    final empty = history.records.isEmpty;
    final days = _days(records).toList(growable: false);
    final now = DateTime.fromMillisecondsSinceEpoch(
      ref.read(historyNowProvider)(),
    );
    final headingExtent = _DayHeading.extentOf(context);
    // 已包含悬浮在安全区之上的迷你播放条。
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AlistenScaffold(
      background: const PageGlow(),
      // 提示出现在筛选框下方，不挡住正在输入的内容。
      topBar: ToastClearance(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AlistenTopBar(
              leading: IconCircleButton(
                icon: Icons.arrow_back_rounded,
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
                    icon: Icons.ios_share_rounded,
                    semanticLabel: '导出播放历史',
                    style: IconCircleButtonStyle.plain,
                    onPressed: empty ? null : () => unawaited(_export()),
                  ),
                IconCircleButton(
                  icon: Icons.delete_sweep_rounded,
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
                  icon: Icons.search_rounded,
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
      // 内容不足一屏时不会滚动，只有尺寸变化通知，两种都要监听才能放宽窗口。
      body: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) =>
            _onScroll(notification.depth, notification.metrics, days.length),
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (notification) =>
              _onScroll(notification.depth, notification.metrics, days.length),
          child: _list(
            history,
            records,
            days,
            now,
            headingExtent,
            bottom,
            currentOrigin,
          ),
        ),
      ),
    );
  }

  Widget _list(
    HistoryState history,
    List<PlayRecord> records,
    List<MapEntry<DateTime, List<PlayRecord>>> days,
    DateTime now,
    double headingExtent,
    double bottom,
    String currentOrigin,
  ) {
    return CustomScrollView(
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (history.records.isEmpty)
          SliverFillRemaining(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: const EmptyState(
                icon: Icons.history_rounded,
                title: '还没有播放记录',
                message: '在房间里听过的歌会记在这里，只保存在这台设备上。',
              ),
            ),
          )
        else if (records.isEmpty)
          SliverFillRemaining(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: '没有匹配“${history.query.trim()}”的记录',
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
            ),
          ),
          for (final day in days.take(_dayWindow))
            SliverMainAxisGroup(
              key: ValueKey(day.key),
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _DayHeading(
                    label: _dayLabel(day.key, now),
                    count: day.value.length,
                    extent: headingExtent,
                  ),
                ),
                SliverList.builder(
                  itemCount: day.value.length,
                  itemBuilder: (context, index) {
                    final record = day.value[index];
                    return _PlayRow(
                      key: ValueKey(_identityOf(record)),
                      record: record,
                      currentOrigin: currentOrigin,
                      onPick: _pick,
                      onDelete: () => _delete(record),
                    );
                  },
                ),
              ],
            ),
          SliverPadding(
            padding: EdgeInsets.only(bottom: bottom + AlistenSpacing.xl),
          ),
        ],
      ],
    );
  }
}

// 按本地日期分组，组按首次出现的顺序排列；时钟回拨时同一天也只有一组。
Iterable<MapEntry<DateTime, List<PlayRecord>>> _days(List<PlayRecord> records) {
  final days = <DateTime, List<PlayRecord>>{};
  for (final record in records) {
    final time = DateTime.fromMillisecondsSinceEpoch(record.playedAtMs);
    days
        .putIfAbsent(DateTime(time.year, time.month, time.day), () => [])
        .add(record);
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

// 同一房间的同一首歌再次播放会得到新的记录，所以要带上播放时间。
String _identityOf(PlayRecord record) {
  return '${record.serverOrigin}/${record.roomId}/'
      '${record.track.source.name}:${record.track.id}@${record.playedAtMs}';
}

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
    required this.record,
    required this.currentOrigin,
    required this.onPick,
    required this.onDelete,
    super.key,
  });

  final PlayRecord record;
  final String currentOrigin;
  final PickSong onPick;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final meta = record.meta;
    return Dismissible(
      key: ValueKey(_identityOf(record)),
      direction: DismissDirection.endToStart,
      movementDuration: AlistenDurations.of(context, AlistenDurations.short),
      resizeDuration: AlistenDurations.of(context, AlistenDurations.short),
      onDismissed: (_) => onDelete(),
      background: ColoredBox(
        color: colors.danger.withValues(alpha: AlistenTint.fill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.page),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(
                Icons.delete_rounded,
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
        subtitle: [
          meta.artist,
          record.roomName,
          if (record.serverOrigin != currentOrigin)
            originAuthority(record.serverOrigin),
        ].where((part) => part.isNotEmpty).join(' · '),
        coverUrl: meta.coverUrl,
        semanticActions: {const CustomSemanticsAction(label: '删除'): onDelete},
        padding: const EdgeInsets.fromLTRB(
          AlistenSpacing.page,
          AlistenSpacing.xxs,
          AlistenSpacing.xs,
          AlistenSpacing.xxs,
        ),
        trailing: PickControl(
          track: record.track,
          title: meta.title,
          label: '再点一次《${meta.title}》',
          subtle: true,
          onPick: onPick,
        ),
      ),
    );
  }
}
