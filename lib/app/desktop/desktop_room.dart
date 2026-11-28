import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/app/desktop/desktop_room_shell.dart';
import 'package:alisten/app/desktop/desktop_room_transport.dart';
import 'package:alisten/app/feedback.dart';
import 'package:alisten/app/room/connection_pill.dart';
import 'package:alisten/app/room/room_actions.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/chat/index.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/cover_flight.dart';
import 'package:alisten/shared/ui/glass_action_group.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/window_chrome.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 桌面窗口的房间页：左边是封面和这首歌的信息，旁边是歌词，底部是播放控制。队列
/// 和聊天由窗口骨架显示在右侧。
class DesktopRoomStage extends StatelessWidget {
  const DesktopRoomStage({required this.roomRef, super.key});

  final String roomRef;

  @override
  Widget build(BuildContext context) => _HeldWhileOpening(
    window: DesktopRoomScope.of(context).window,
    child: _Stage(roomRef: roomRef),
  );
}

// 窗口打开的途中才连上房间时，等它停稳再排出里面的内容并淡入。打开途中画的是
// 窗口的快照，这时排出来的内容既看不见，又让打开的动画掉帧。窗口打开的第一帧
// 就在的内容照常排出：从迷你播放条回来时，封面要有地方落。
class _HeldWhileOpening extends StatefulWidget {
  const _HeldWhileOpening({required this.window, required this.child});

  final ModalRoute<Object?>? window;
  final Widget child;

  @override
  State<_HeldWhileOpening> createState() => _HeldWhileOpeningState();
}

class _HeldWhileOpeningState extends State<_HeldWhileOpening> {
  late bool _held;
  late final bool _wasHeld;
  Animation<double>? _entrance;

  @override
  void initState() {
    super.initState();
    final entrance = widget.window?.animation;
    _held =
        entrance != null &&
        entrance.status == AnimationStatus.forward &&
        entrance.value > 0;
    _wasHeld = _held;
    if (_held) _entrance = entrance!..addStatusListener(_release);
  }

  void _release(AnimationStatus status) {
    if (status == AnimationStatus.forward) return;
    _entrance?.removeStatusListener(_release);
    setState(() => _held = false);
  }

  @override
  void dispose() {
    if (_held) _entrance?.removeStatusListener(_release);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_held) return const SizedBox.expand();
    if (!_wasHeld) return widget.child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AlistenDurations.of(context, AlistenDurations.short),
      curve: AlistenCurves.standard,
      builder: (context, shown, child) => Opacity(opacity: shown, child: child),
      child: widget.child,
    );
  }
}

class _Stage extends ConsumerWidget {
  const _Stage({required this.roomRef});

  final String roomRef;

  static const _barHeight = 48.0;
  static const _coverOfHeight = 0.40;
  static const _minCover = 180.0;
  static const _maxCover = 420.0;

  // 封面超过这么大时，歌词与歌名按比例放大。
  static const _plainCover = 260.0;
  static const _maxLyricScale = 1.30;
  static const _maxMetaScale = 1.22;

  // 歌词每行自带 AlistenSpacing.page 的内边距，看到的间距比这里多这么多。
  static const _minGap = 36.0;
  static const _maxGap = 140.0;
  static const _maxContentWidth =
      _maxCover + _maxGap + LyricsView.baseMaxWidth * _maxLyricScale;
  static const _minLyricsWidth = 280.0;
  static const _minStartEdge = 48.0;
  static const _minEndEdge = 24.0;
  static const _minCenteredContentWidth = 912.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    final router = GoRouter.of(context);
    final room = ref.watch(
      roomControllerProvider.select((room) {
        final snapshot = room.snapshot;
        final id = room.activeRoomId;
        if (snapshot == null || id == null) return null;
        return (
          id: id,
          slug: room.roomSlug,
          name: snapshot.room.name,
          online: snapshot.onlineCount,
          capacity: snapshot.room.capacity,
          nowPlaying: snapshot.nowPlaying,
          status: room.status,
          nextRetryAt: room.nextRetryAt,
          mayReconnectNow: room.mayReconnectNow,
        );
      }),
    );
    if (room == null) return const SizedBox.shrink();
    final stageScope = SettledStageWidth.maybeOf(context);
    final settled = stageScope?.width;
    final panelVisible = stageScope?.panelVisible ?? true;
    final bar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.sm),
      child: Row(
        children: [
          _Action(
            icon: AlistenIcons.caretDown,
            label: '收起房间',
            onPressed: () => context.go('/'),
          ),
          const SizedBox(width: AlistenSpacing.xxs),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: ActionMenuButton(
                    semanticLabel: '房间操作',
                    below: true,
                    entries: [
                      ActionMenuEntry(
                        icon: AlistenIcons.userPlus,
                        label: '复制邀请链接',
                        onSelected: () =>
                            copyInviteLink(ref, id: room.id, slug: room.slug),
                      ),
                      ActionMenuEntry(
                        icon: AlistenIcons.signOut,
                        label: '退出房间',
                        danger: true,
                        onSelected: DesktopRoomScope.of(context).leave,
                      ),
                    ],
                    trigger: (open, toggle) => Pressable(
                      onPressed: toggle,
                      semanticLabel:
                          '${room.name}，${room.online} / ${room.capacity} 人在线，'
                          '房间操作',
                      expanded: open,
                      focusRadius: BorderRadius.circular(AlistenRadii.sm),
                      touchTarget: const BoxConstraints(minHeight: 32),
                      child: ExcludeSemantics(
                        child: AnimatedContainer(
                          duration: AlistenDurations.of(
                            context,
                            AlistenDurations.short,
                          ),
                          curve: AlistenCurves.standard,
                          decoration: BoxDecoration(
                            color: open
                                ? colors.onGlass.withValues(alpha: 0.08)
                                : colors.onGlass.withValues(alpha: 0),
                            borderRadius: BorderRadius.circular(
                              AlistenRadii.sm,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AlistenSpacing.xs,
                            vertical: AlistenSpacing.xxs + 1,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  room.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AlistenTypography.bodyStrong.copyWith(
                                    color: colors.onGlass,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AlistenSpacing.xs),
                              Text(
                                '${room.online} / ${room.capacity}',
                                style: AlistenTypography.caption.copyWith(
                                  color: colors.success,
                                ),
                              ),
                              const SizedBox(width: AlistenSpacing.xxs),
                              AnimatedRotation(
                                turns: open ? 0.5 : 0,
                                duration: AlistenDurations.of(
                                  context,
                                  const Duration(milliseconds: 260),
                                ),
                                curve: Curves.easeOutBack,
                                child: Icon(
                                  AlistenIcons.caretDown,
                                  size: 12,
                                  color: colors.onGlassMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AlistenSpacing.sm),
                ConnectionPill(
                  status: room.status,
                  nextRetryAt: room.nextRetryAt,
                  onRetryNow: room.mayReconnectNow
                      ? () => unawaited(
                          ref
                              .read(roomControllerProvider.notifier)
                              .checkConnection(),
                        )
                      : null,
                ),
              ],
            ),
          ),
          // 这两个入口平时在右侧面板里。
          if (!panelVisible) ...[
            const SizedBox(width: AlistenSpacing.sm),
            _PickActions(
              onSearch: () =>
                  unawaited(context.push<void>('/r/$roomRef/search')),
              onFromPlaylists: () =>
                  unawaited(context.push<void>('/r/$roomRef/from-playlists')),
            ),
          ],
          const WindowButtonsGap(),
        ],
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          SizedBox(
            height: _barHeight,
            child: WindowDragBar(child: bar),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 封面只随高度变，放不下封面和歌词时不显示封面；右侧面板滑动的途中按
                // 停稳后的宽度排版，歌词不会来回挪。
                final width = math.min(
                  constraints.maxWidth,
                  settled ?? constraints.maxWidth,
                );
                final cover = (constraints.maxHeight * _coverOfHeight).clamp(
                  _minCover,
                  _maxCover,
                );
                final sizeT = ((cover - _minCover) / (_maxCover - _minCover))
                    .clamp(0.0, 1.0);
                final scaleT =
                    ((cover - _plainCover) / (_maxCover - _plainCover)).clamp(
                      0.0,
                      1.0,
                    );
                final fullLyricScale = 1 + scaleT * (_maxLyricScale - 1);
                final metaScale = 1 + scaleT * (_maxMetaScale - 1);
                final gap = _minGap + (_maxGap - _minGap) * sizeT * sizeT;
                final minLyricsWidth = _minLyricsWidth * fullLyricScale;
                final showCover =
                    width >=
                    _minStartEdge + cover + gap + minLyricsWidth + _minEndEdge;
                final lyricScale = showCover
                    ? fullLyricScale
                    : math.min(
                        fullLyricScale,
                        (width / LyricsView.baseMaxWidth).clamp(
                          1.0,
                          _maxLyricScale,
                        ),
                      );
                final maxLyricWidth = LyricsView.baseMaxWidth * lyricScale;
                final contentWidth = math.max(
                  _minCenteredContentWidth,
                  cover + gap + maxLyricWidth,
                );
                final startEdge = showCover
                    ? math.max(
                        _minStartEdge,
                        (constraints.maxWidth - contentWidth) / 2,
                      )
                    : 0.0;
                final endEdge = showCover
                    ? math.max(
                        _minEndEdge,
                        (constraints.maxWidth - contentWidth) / 2,
                      )
                    : 0.0;
                final settledStartEdge = showCover
                    ? math.max(_minStartEdge, (width - contentWidth) / 2)
                    : 0.0;
                final settledEndEdge = showCover
                    ? math.max(_minEndEdge, (width - contentWidth) / 2)
                    : 0.0;
                final lyricColumnWidth = showCover
                    ? math.max(
                        0.0,
                        width - settledStartEdge - settledEndEdge - cover - gap,
                      )
                    : width;
                return Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: startEdge,
                    end: endEdge,
                  ),
                  child: Row(
                    children: [
                      if (showCover) ...[
                        SizedBox(
                          width: cover,
                          child: _NowPlaying(
                            nowPlaying: room.nowPlaying,
                            coverSize: cover,
                            metaScale: metaScale,
                            save: switch (room.nowPlaying?.entry) {
                              final entry? => SaveToPlaylistButton(
                                track: entry.track,
                                title: entry.meta.title,
                                onOpenAccount: () =>
                                    router.go('/settings/account'),
                                onNotice: ref
                                    .read(toastControllerProvider)
                                    .show,
                              ),
                              null => null,
                            },
                          ),
                        ),
                        SizedBox(width: gap),
                      ],
                      Expanded(
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(
                              MediaQuery.textScalerOf(context)
                                  .scale(lyricScale),
                            ),
                          ),
                          child: LyricsView(
                            columnWidth: lyricColumnWidth,
                            maxWidth: maxLyricWidth,
                            alignment: showCover
                                ? AlignmentDirectional.topStart
                                : Alignment.topCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const DesktopRoomTransport(maxWidth: _maxContentWidth),
        ],
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({
    required this.nowPlaying,
    required this.coverSize,
    required this.metaScale,
    required this.save,
  });

  final NowPlaying? nowPlaying;
  final double coverSize;
  final double metaScale;
  final Widget? save;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final entry = nowPlaying?.entry;
    final requester = entry == null
        ? null
        : entry.auto
        ? '自动推荐'
        : switch (entry.requestedBy) {
            final member? => '${member.name} 点歌',
            null => null,
          };
    final titleStyle = AlistenTypography.title.copyWith(
      color: colors.onGlass,
      fontSize: AlistenTypography.title.fontSize! * metaScale,
    );
    final subtitleStyle = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
      fontSize: AlistenTypography.secondary.fontSize! * metaScale,
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoverArt(
          url: entry?.meta.coverUrl,
          size: coverSize,
          radius: AlistenRadii.lg,
          shadow: true,
          // 和迷你播放条的封面是同一个：进出房间时它在两处之间飞过去。
          heroTag: entry == null ? null : 'cover-${entry.id}',
        ),
        SizedBox(height: AlistenSpacing.md + (metaScale - 1) * 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: AlistenDurations.of(context, AlistenDurations.medium),
                layoutBuilder: (current, previous) => Stack(
                  alignment: AlignmentDirectional.topStart,
                  children: [...previous, ?current],
                ),
                child: Column(
                  key: ValueKey(entry?.id),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry?.meta.title ?? '房间暂时没有播放',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    if (entry != null) ...[
                      const SizedBox(height: AlistenSpacing.xxs),
                      Text(
                        [
                          entry.meta.artist,
                          ?requester,
                        ].where((part) => part.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (save case final save?) ...[
              const SizedBox(width: AlistenSpacing.xs),
              save,
            ],
          ],
        ),
      ],
    );
  }
}

// 只有图标的按钮，名称由读屏读出。
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconCircleButton(
      icon: icon,
      semanticLabel: label,
      style: IconCircleButtonStyle.plain,
      diameter: AlistenSizes.rowAction,
      iconSize: AlistenSizes.iconSm,
      onPressed: onPressed,
    );
  }
}

// 已经在其中一页上时，那一页的入口不给。
class _PickActions extends StatelessWidget {
  const _PickActions({required this.onSearch, required this.onFromPlaylists});

  final VoidCallback? onSearch;
  final VoidCallback? onFromPlaylists;

  @override
  Widget build(BuildContext context) {
    return GlassActionGroup(
      actions: [
        if (onSearch case final search?)
          GlassAction(
            icon: AlistenIcons.magnifyingGlass,
            semanticLabel: '搜歌',
            onPressed: search,
          ),
        if (onFromPlaylists case final playlists?)
          GlassAction(
            icon: AlistenIcons.playlist,
            semanticLabel: '从歌单点歌',
            onPressed: playlists,
          ),
      ],
    );
  }
}

/// 中间区域停稳时的宽度与右侧面板可见性。右侧面板展开或收起的途中宽度不变，
/// 歌词照它排一次版，不必跟着逐帧重排。
class SettledStageWidth extends InheritedWidget {
  const SettledStageWidth({
    required this.width,
    required super.child,
    this.panelVisible = true,
    super.key,
  });

  final double width;
  final bool panelVisible;

  static SettledStageWidth? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettledStageWidth>();

  @override
  bool updateShouldNotify(SettledStageWidth oldWidget) =>
      width != oldWidget.width || panelVisible != oldWidget.panelVisible;
}

/// 所在房间的队列和聊天，同时显示且可拖动分隔条调整各自高度。离开房间页面时
/// 面板会被移除，所以队列所占的比例 [queueFraction] 由上层保存。
class DesktopRoomPanel extends StatelessWidget {
  const DesktopRoomPanel({
    required this.queueFraction,
    required this.onQueueFractionChanged,
    this.onPickSongs,
    this.onPickFromPlaylists,
    super.key,
  });

  final double queueFraction;
  final ValueChanged<double> onQueueFractionChanged;
  final VoidCallback? onPickSongs;
  final VoidCallback? onPickFromPlaylists;

  static const defaultQueueFraction = 5 / 9;
  static const splitterHeight = 14.0;
  static const minPaneHeight = 156.0;

  @override
  Widget build(BuildContext context) => _HeldWhileOpening(
    window: DesktopRoomScope.of(context).window,
    child: _Panel(
      queueFraction: queueFraction,
      onQueueFractionChanged: onQueueFractionChanged,
      onPickSongs: onPickSongs,
      onPickFromPlaylists: onPickFromPlaylists,
    ),
  );
}

class _Panel extends ConsumerStatefulWidget {
  const _Panel({
    required this.queueFraction,
    required this.onQueueFractionChanged,
    this.onPickSongs,
    this.onPickFromPlaylists,
  });

  final double queueFraction;
  final ValueChanged<double> onQueueFractionChanged;
  final VoidCallback? onPickSongs;
  final VoidCallback? onPickFromPlaylists;

  @override
  ConsumerState<_Panel> createState() => _PanelState();
}

class _PanelState extends ConsumerState<_Panel> {
  double? _dragStartY;
  double? _dragStartQueueHeight;

  @override
  Widget build(BuildContext context) {
    final toasts = ref.read(toastControllerProvider);
    final router = GoRouter.of(context);
    void openAccount() => router.go('/settings/account');
    final chrome = WindowChrome.of(context);
    final top = chrome.active
        ? chrome.titleBarHeight + AlistenSpacing.xxs
        : AlistenSpacing.sm;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        top,
        AlistenSpacing.sm,
        AlistenSpacing.sm,
      ),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        radius: AlistenRadii.md,
        child: QueueCoverWarmup(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final available = math.max(
                0.0,
                constraints.maxHeight - DesktopRoomPanel.splitterHeight,
              );
              final minPane = math.min(
                DesktopRoomPanel.minPaneHeight,
                available / 2,
              );
              final maxQueue = math.max(minPane, available - minPane);
              final queueHeight = (available * widget.queueFraction).clamp(
                minPane,
                maxQueue,
              );
              final chatHeight = math.max(0.0, available - queueHeight);
              return Column(
                children: [
                  SizedBox(
                    height: queueHeight,
                    child: FlightMark(
                      tag: queueFlightArea,
                      child: QueueView(
                        pickActions: _PickActions(
                          onSearch: widget.onPickSongs,
                          onFromPlaylists: widget.onPickFromPlaylists,
                        ),
                        onResult: (result, success) => reportMutation(
                          toasts,
                          result,
                          success: (_) => success,
                        ),
                        onCopyTitle: (title) => copySongTitle(toasts, title),
                        onSaveToPlaylist: (context, track, title) => unawaited(
                          showSaveToPlaylistSheet(
                            context,
                            SaveOneTrack(track: track, title: title),
                            onOpenAccount: openAccount,
                            onNotice: toasts.show,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _PanelSplitter(
                    onDragStart: (globalY) {
                      _dragStartY = globalY;
                      _dragStartQueueHeight = queueHeight;
                    },
                    onDragMove: (globalY) {
                      final startY = _dragStartY;
                      final startHeight = _dragStartQueueHeight;
                      if (startY == null ||
                          startHeight == null ||
                          available <= 0) {
                        return;
                      }
                      final next = (startHeight + (globalY - startY)).clamp(
                        minPane,
                        maxQueue,
                      );
                      final fraction = next / available;
                      if (fraction != widget.queueFraction) {
                        widget.onQueueFractionChanged(fraction);
                      }
                    },
                    onDragEnd: () {
                      _dragStartY = null;
                      _dragStartQueueHeight = null;
                    },
                    onReset: () {
                      _dragStartY = null;
                      _dragStartQueueHeight = null;
                      widget.onQueueFractionChanged(
                        DesktopRoomPanel.defaultQueueFraction,
                      );
                    },
                    onNudge: (delta) {
                      if (available <= 0) return;
                      widget.onQueueFractionChanged(
                        (queueHeight + delta).clamp(minPane, maxQueue) /
                            available,
                      );
                    },
                  ),
                  SizedBox(height: chatHeight, child: const ChatView()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PanelSplitter extends StatefulWidget {
  const _PanelSplitter({
    required this.onDragStart,
    required this.onDragMove,
    required this.onDragEnd,
    required this.onReset,
    required this.onNudge,
  });

  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragMove;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  /// 用键盘上下方向键挪动，参数是挪多少。
  final ValueChanged<double> onNudge;

  static const _step = 24.0;

  @override
  State<_PanelSplitter> createState() => _PanelSplitterState();
}

class _PanelSplitterState extends State<_PanelSplitter> {
  bool _hovered = false;
  bool _dragging = false;
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      _ => 0,
    };
    if (direction == 0) return KeyEventResult.ignored;
    widget.onNudge(direction * _PanelSplitter._step);
    return KeyEventResult.handled;
  }

  void _endDrag() {
    widget.onDragEnd();
    if (_dragging) setState(() => _dragging = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final active = _hovered || _dragging || _focused;
    final pillAlpha = _dragging || _focused
        ? 0.55
        : _hovered
        ? 0.35
        : 0.16;
    return Semantics(
      label: '调整队列与聊天高度',
      hint: '上下拖动或按上下方向键调整高度，双击恢复默认比例',
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeRow,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            key: const ValueKey('desktop-room-panel-splitter'),
            behavior: HitTestBehavior.opaque,
            // 从按下的位置起算，高度按指针的绝对位置定，与指针 1:1 对应。
            dragStartBehavior: DragStartBehavior.down,
            onVerticalDragStart: (details) {
              widget.onDragStart(details.globalPosition.dy);
              setState(() => _dragging = true);
            },
            onVerticalDragUpdate: (details) =>
                widget.onDragMove(details.globalPosition.dy),
            onVerticalDragEnd: (_) => _endDrag(),
            onVerticalDragCancel: _endDrag,
            onDoubleTap: widget.onReset,
            child: SizedBox(
              height: DesktopRoomPanel.splitterHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: AlistenSizes.hairline,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AlistenSpacing.md,
                    ),
                    color: colors.onGlass.withValues(
                      alpha: active ? 0.16 : 0.08,
                    ),
                  ),
                  AnimatedContainer(
                    duration: AlistenDurations.of(
                      context,
                      AlistenDurations.short,
                    ),
                    width: active ? 44 : 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onGlass.withValues(alpha: pillAlpha),
                      borderRadius: BorderRadius.circular(AlistenRadii.pill),
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
