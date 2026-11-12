import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/queue/application/queue_controller.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/edge_fade.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/section_header.dart';
import 'package:alisten/shared/ui/segmented_pills.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [success] 是变更成功时展示的文字。结果须展示在不随页面消失的地方，如提示。
typedef QueueResultCallback = void Function(
  MutationResult<Object?> result,
  String success,
);

const _panelMargin = EdgeInsets.symmetric(horizontal: AlistenSpacing.sm);
const _headerPadding = EdgeInsets.fromLTRB(
  AlistenSpacing.page,
  AlistenSpacing.xl,
  AlistenSpacing.page,
  AlistenSpacing.sm,
);
const _rowPadding = EdgeInsets.fromLTRB(
  AlistenSpacing.sm,
  AlistenSpacing.xs,
  AlistenSpacing.xxs,
  AlistenSpacing.xs,
);

const _dividerInset =
    AlistenSpacing.sm + AlistenSizes.rowCover + AlistenSpacing.sm;

const _modes = [
  (RoomPlayMode.sequential, '顺序', AlistenIcons.arrowRight, '已切换为顺序播放'),
  (RoomPlayMode.rotation, '轮流', AlistenIcons.users, '已切换为轮流播放'),
  (RoomPlayMode.random, '随机', AlistenIcons.shuffle, '已切换为随机播放'),
];

const _bounceScale = 1.4;

// 播放模式一行静止时要完整落在这条渐隐带之下，否则顶边被淡化，看起来像被上方
// 的进度条挡住一截。
const _topFade = AlistenSpacing.md;

Widget _faded(Widget child) {
  return SliverToBoxAdapter(child: EdgeFadeItem(child: child));
}

typedef SaveTrackCallback = void Function(
  BuildContext context,
  Track track,
  String title,
);

/// 列表只随房间快照变化，发起变更时不做乐观更新。
///
/// 每行只露出一个操作（等待中的歌是点赞），其余收进“⋯”：窄屏大字号下多露一个
/// 按钮，歌名就只剩几个字。
class QueueView extends ConsumerWidget {
  const QueueView({
    required this.onResult,
    required this.onCopyTitle,
    this.onSaveToPlaylist,
    super.key,
  });

  final QueueResultCallback onResult;
  final ValueChanged<String> onCopyTitle;

  /// 歌单功能依赖队列，这里反过来依赖它会形成循环，所以由 app 层传入。传入的
  /// context 是这一行的，从它打开的面板沿用房间的配色。
  final SaveTrackCallback? onSaveToPlaylist;

  Widget _menu(
    QueueEntry entry, {
    bool removable = false,
    VoidCallback? onRemove,
  }) {
    return _EntryMenu(
      entry: entry,
      onCopyTitle: onCopyTitle,
      onSaveToPlaylist: onSaveToPlaylist,
      removable: removable,
      onRemove: onRemove,
    );
  }

  Future<bool> _like(QueueController queue, QueueEntry entry) async {
    final result = await queue.like(entry.id);
    onResult(result, '已点赞');
    return result is MutationSucceeded<int>;
  }

  Future<void> _remove(
    BuildContext context,
    QueueController queue,
    QueueEntry entry,
  ) async {
    final confirmed = await showConfirmSheet(
      context,
      title: '移除这首歌？',
      message: '《${entry.meta.title}》会从等待的歌里移除。',
      confirmLabel: '移除',
      confirmIcon: AlistenIcons.trash,
    );
    if (!confirmed) return;
    onResult(await queue.remove(entry.id), '已移除');
  }

  Future<void> _setMode(
    QueueController queue,
    RoomPlayMode mode,
    String success,
  ) async {
    onResult(await queue.setPlayMode(mode), success);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(
      roomControllerProvider.select((room) => room.snapshot),
    );
    final mine = ref.watch(
      roomControllerProvider.select((room) => room.member?.id),
    );
    final connected = ref.watch(
      roomControllerProvider.select(
        (room) => room.status == RoomConnectionStatus.open,
      ),
    );
    final busy = ref.watch(queueControllerProvider);
    final queue = ref.read(queueControllerProvider.notifier);
    if (snapshot == null) {
      return const Center(
        child: BusyIndicator(size: AlistenSizes.iconLg, semanticLabel: '加载中'),
      );
    }
    final playing = snapshot.nowPlaying?.entry;
    final pending = snapshot.pending;
    final waiting = snapshot.items;
    final indexOf = {
      for (var index = 0; index < waiting.length; index++)
        waiting[index].id: index,
    };
    return RepaintBoundary(
      child: EdgeFade(
        top: _topFade,
        bottom: AlistenSpacing.xxl,
        child: CustomScrollView(
          // 可能与歌词或聊天同时显示（如滑动切换途中、两栏布局），不能共用
          // primary 控制器。
          primary: false,
          slivers: [
            _faded(
              _PlayModeRow(
                selected: snapshot.playMode,
                busy: busy.changingMode,
                onChanged: connected && !busy.changingMode
                    ? (mode) {
                        if (mode == snapshot.playMode) return;
                        unawaited(
                          _setMode(
                            queue,
                            mode,
                            _modes.firstWhere((m) => m.$1 == mode).$4,
                          ),
                        );
                      }
                    : null,
              ),
            ),
            if (playing != null) ...[
              _faded(const SectionHeader('正在播放', padding: _headerPadding)),
              _faded(
                _Panel(
                  child: _EntryRow(
                    entry: playing,
                    mine: mine,
                    onCopyTitle: onCopyTitle,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Playing(likes: playing.likes),
                        _menu(playing),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (pending != null) ...[
              _faded(
                SectionHeader(
                  '下一首',
                  padding: _headerPadding,
                  trailing: pending.status == QueueEntryStatus.preparing
                      ? const _Preparing()
                      : null,
                ),
              ),
              _faded(
                _Panel(
                  child: _EntryRow(
                    entry: pending,
                    mine: mine,
                    onCopyTitle: onCopyTitle,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LikeCount(likes: pending.likes),
                        _menu(pending),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (playing == null && pending == null && waiting.isEmpty)
              // 不用 SliverFillRemaining(hasScrollBody: false)：它会测量空状态
              // 的固有高度，而空状态给不出固有高度。
              SliverLayoutBuilder(
                builder: (context, constraints) => SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.remainingPaintExtent,
                    ),
                    // 只让空状态本身渐隐：外框总会伸进底部渐隐带，渐隐外框
                    // 会让整块离屏绘制。
                    child: Center(
                      child: EdgeFadeItem(
                        child: EmptyState(
                          icon: AlistenIcons.queue,
                          title: _noSongs,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else ...[
              _faded(
                SectionHeader(
                  '等待中 ${waiting.length} 首',
                  padding: _headerPadding,
                ),
              ),
              if (waiting.isEmpty)
                _faded(const _NoneWaiting())
              else
                SliverList.builder(
                  itemCount: waiting.length,
                  findChildIndexCallback: (key) =>
                      key is ValueKey<String> ? indexOf[key.value] : null,
                  // 自动添加的重绘边界包在 `EdgeFadeItem` 外，滚动时它不会
                  // 重绘，渐隐会停在旧位置，所以边界放在它内部。
                  addRepaintBoundaries: false,
                  itemBuilder: (context, index) {
                    final entry = waiting[index];
                    final inFlight = busy.entries.contains(entry.id);
                    final enabled = connected && !inFlight;
                    return EdgeFadeItem(
                      key: ValueKey(entry.id),
                      child: RepaintBoundary(
                        child: _Panel(
                          last: index == waiting.length - 1,
                          child: _EntryRow(
                            entry: entry,
                            mine: mine,
                            onCopyTitle: onCopyTitle,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _LikeButton(
                                  likes: entry.likes,
                                  label:
                                      '点赞《${entry.meta.title}》，${entry.likes} 个赞',
                                  busy: inFlight,
                                  onPressed: enabled
                                      ? () => _like(queue, entry)
                                      : null,
                                ),
                                _menu(
                                  entry,
                                  removable: true,
                                  onRemove: enabled
                                      ? () => unawaited(
                                          _remove(context, queue, entry),
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SliverPadding(
                padding: EdgeInsets.only(bottom: AlistenSpacing.xl),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// 点歌的入口只有底栏（平板在顶栏）那一个，这里不再放按钮。
const _noSongs = '还没有歌，点一首吧';

// 字体较大时选项换到标签下方，选项文字才不会被截断。
class _PlayModeRow extends StatelessWidget {
  const _PlayModeRow({
    required this.selected,
    required this.busy,
    required this.onChanged,
  });

  final RoomPlayMode selected;
  final bool busy;
  final ValueChanged<RoomPlayMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.textScalerOf(context)
        .scale(AlistenSizes.threeChoiceWidth);
    return Padding(
      // 右边缘与下方的面板对齐。
      padding: const EdgeInsets.fromLTRB(
        AlistenSpacing.page,
        _topFade,
        AlistenSpacing.sm,
        0,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlistenSpacing.xs,
        runSpacing: AlistenSpacing.xs,
        children: [
          // 选项组的语义标签已读出，避免重复朗读。
          ExcludeSemantics(
            child: Text(
              '播放模式',
              style: AlistenTypography.bodyStrong.copyWith(
                color: AlistenColors.of(context).onGlass,
              ),
            ),
          ),
          SizedBox(
            width: width,
            child: Semantics(
              container: true,
              label: '播放模式',
              value: busy ? busySemanticValue : null,
              child: SegmentedPills<RoomPlayMode>(
                segments: [
                  for (final (mode, label, icon, _) in _modes)
                    PillSegment(value: mode, label: label, icon: icon),
                ],
                selected: selected,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 同一列表的各行拼成一整块面板：首行圆上角，末行圆下角，行间有细分隔线。
// 队列的行直接排在房间背景上，只用细线隔开，不再套一层玻璃卡片。
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.last = true});

  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _panelMargin,
      child: CustomPaint(
        painter: _PanelPainter(
          stroke: AlistenColors.of(context).glassStroke,
          last: last,
        ),
        child: child,
      ),
    );
  }
}

class _PanelPainter extends CustomPainter {
  const _PanelPainter({required this.stroke, required this.last});

  final Color stroke;
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    if (last) return;
    const width = AlistenSizes.hairline;
    canvas.drawLine(
      Offset(_dividerInset, size.height - width / 2),
      Offset(size.width - AlistenSpacing.sm, size.height - width / 2),
      Paint()
        ..color = stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_PanelPainter oldDelegate) {
    return stroke != oldDelegate.stroke || last != oldDelegate.last;
  }
}

// 不使用 Hero 标签：正在播放的封面已在房间头部。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.mine,
    required this.onCopyTitle,
    this.trailing,
  });

  final QueueEntry entry;

  /// 本机成员的 ID。
  final String? mine;
  final ValueChanged<String> onCopyTitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final by = entry.requestedBy;
    final who = by == null
        ? (entry.auto ? '自动推荐' : null)
        : (by.id == mine ? '我' : by.name);
    return TrackRow(
      title: entry.meta.title,
      subtitle: who == null ? entry.meta.artist : '$who · ${entry.meta.artist}',
      subtitleLeading: by != null
          ? MemberAvatar(
              name: by.name,
              imageUrl: by.avatarUrl(AlistenSizes.memberTag),
              size: AlistenSizes.memberTag,
            )
          : entry.auto
          ? const MemberAvatar.icon(
              AlistenIcons.sparkle,
              size: AlistenSizes.memberTag,
            )
          : null,
      coverUrl: entry.meta.coverUrl,
      onLongPress: () => onCopyTitle(entry.meta.title),
      longPressHint: copyTitleHint,
      trailing: trailing,
      padding: _rowPadding,
    );
  }
}

class _EntryMenu extends StatelessWidget {
  const _EntryMenu({
    required this.entry,
    required this.onCopyTitle,
    required this.onSaveToPlaylist,
    required this.removable,
    required this.onRemove,
  });

  final QueueEntry entry;
  final ValueChanged<String> onCopyTitle;
  final SaveTrackCallback? onSaveToPlaylist;

  /// 只有等待中的歌可以移除；[onRemove] 为 null 时这一项暂不可用（如未连接）。
  final bool removable;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final title = entry.meta.title;
    final save = onSaveToPlaylist;
    final remove = onRemove;
    return ActionMenuButton(
      semanticLabel: '《$title》的更多操作',
      iconSize: AlistenSizes.iconSm,
      entries: [
        if (save != null)
          ActionMenuEntry(
            icon: AlistenIcons.listPlus,
            label: '保存到歌单',
            onSelected: () => save(context, entry.track, title),
          ),
        ActionMenuEntry(
          icon: AlistenIcons.copy,
          label: copyTitleHint,
          onSelected: () => onCopyTitle(title),
        ),
        if (removable)
          ActionMenuEntry(
            icon: AlistenIcons.minusCircle,
            label: '移除',
            danger: true,
            enabled: remove != null,
            onSelected: () => remove?.call(),
          ),
      ],
    );
  }
}

class _NoneWaiting extends StatelessWidget {
  const _NoneWaiting();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: _rowPadding,
        child: Text(
          _noSongs,
          style: AlistenTypography.body.copyWith(
            color: AlistenColors.of(context).onGlassMuted,
          ),
        ),
      ),
    );
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) {
    final muted = AlistenColors.of(context).onGlassMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BusyIndicator(size: AlistenSizes.inlineIcon, color: muted),
        const SizedBox(width: AlistenSpacing.xxs),
        Text('准备中', style: AlistenTypography.secondary.copyWith(color: muted)),
      ],
    );
  }
}

class _Playing extends StatelessWidget {
  const _Playing({required this.likes});

  final int likes;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LikeCount(likes: likes),
        const SizedBox(width: AlistenSpacing.xs),
        ExcludeSemantics(
          child: Icon(
            AlistenIcons.waveform,
            size: AlistenSizes.icon,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _LikeCount extends StatelessWidget {
  const _LikeCount({required this.likes});

  final int likes;

  @override
  Widget build(BuildContext context) {
    if (likes <= 0) return const SizedBox.shrink();
    final muted = AlistenColors.of(context).onGlassMuted;
    return Semantics(
      label: '$likes 个赞',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: AlistenSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                AlistenIcons.heart,
                size: AlistenSizes.inlineIcon,
                color: muted,
              ),
              const SizedBox(width: AlistenSpacing.xxs),
              _LikeNumber(likes),
            ],
          ),
        ),
      ),
    );
  }
}

class _LikeNumber extends StatelessWidget {
  const _LikeNumber(this.likes);

  final int likes;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AlistenDurations.of(context, AlistenDurations.short),
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => SlideTransition(
        position: animation.drive(
          Tween(begin: const Offset(0, 0.6), end: Offset.zero),
        ),
        child: FadeTransition(opacity: animation, child: child),
      ),
      // Android 的字号最大 2 倍；iOS 的辅助功能字号下，三位数的点赞数会把 320 pt
      // 宽的行里的歌名挤没。
      child: Text(
        '$likes',
        key: ValueKey(likes),
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2),
        style: AlistenTypography.timecode.copyWith(
          color: AlistenColors.of(context).onGlassMuted,
        ),
      ),
    );
  }
}

class _LikeButton extends StatefulWidget {
  const _LikeButton({
    required this.likes,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final int likes;
  final String label;
  final bool busy;

  /// 返回是否得到确认；为 null 表示现在不能点赞。
  final Future<bool> Function()? onPressed;

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: AlistenDurations.bounce,
  );

  late final Animation<double> _scale = _bounce.drive(
    TweenSequence([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: _bounceScale,
        ).chain(CurveTween(curve: AlistenCurves.standard)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: _bounceScale,
          end: 1.0,
        ).chain(CurveTween(curve: AlistenCurves.bounce)),
        weight: 60,
      ),
    ]),
  );

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  Future<void> _press() async {
    final confirmed = await widget.onPressed!();
    if (!mounted || !confirmed || MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    unawaited(_bounce.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final lit = Theme.of(context).colorScheme.primary;
    final onPressed = widget.onPressed;
    // 预留宽度随字号放大到 1.5 倍为止，否则 320 dp 宽的屏幕上大字号时，等待中
    // 一行的保存、点赞和移除会把标题挤没，整行溢出。
    final countWidth = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: 1.5)
        .scale(AlistenSizes.countWidth);
    return Pressable(
      onPressed: onPressed == null ? null : () => unawaited(_press()),
      semanticLabel: widget.label,
      child: Semantics(
        value: widget.busy ? busySemanticValue : null,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AlistenSizes.minTouchTarget,
              minHeight: AlistenSizes.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlistenSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: AlistenSizes.iconSm,
                    child: widget.busy
                        ? Center(
                            child: BusyIndicator(
                              size: AlistenSizes.inlineIcon,
                              color: colors.onGlassMuted,
                            ),
                          )
                        : AnimatedBuilder(
                            animation: _bounce,
                            builder: (context, _) {
                              final glow = math.sin(math.pi * _bounce.value);
                              return Transform.scale(
                                scale: _scale.value,
                                child: Icon(
                                  _bounce.isAnimating
                                      ? AlistenIcons.heartFill
                                      : AlistenIcons.heart,
                                  size: AlistenSizes.iconSm,
                                  color: Color.lerp(
                                    colors.onGlassMuted,
                                    lit,
                                    glow,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(width: AlistenSpacing.xxs),
                  // 放不下的点赞数缩小到预留宽度之内，不再挤占歌名。
                  SizedBox(
                    width: countWidth,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: _LikeNumber(widget.likes),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
