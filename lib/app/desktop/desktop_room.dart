import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/app/feedback.dart';
import 'package:alisten/app/room/connection_pill.dart';
import 'package:alisten/app/room/room_actions.dart';
import 'package:alisten/features/chat/index.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 桌面窗口里房间页的中间部分：顶上是点歌和房间操作，下面是歌词。队列、
/// 聊天和播放条由窗口骨架常驻显示。
class DesktopRoomStage extends ConsumerWidget {
  const DesktopRoomStage({required this.roomRef, super.key});

  final String roomRef;

  static const _barHeight = 64.0;

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final room = ref.read(roomControllerProvider.notifier);
    if (!await confirmLeavingRoom(context)) return;
    router.go('/');
    unawaited(room.leaveRoom());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(
      roomControllerProvider.select((room) {
        final snapshot = room.snapshot;
        final id = room.activeRoomId;
        if (snapshot == null || id == null) return null;
        return (
          id: id,
          slug: room.roomSlug,
          status: room.status,
          nextRetryAt: room.nextRetryAt,
          mayReconnectNow: room.mayReconnectNow,
        );
      }),
    );
    if (room == null) return const SizedBox.shrink();
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          SizedBox(
            height: _barHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlistenSpacing.lg,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _SearchEntry(
                        onPressed: () =>
                            unawaited(context.push<void>('/r/$roomRef/search')),
                      ),
                    ),
                  ),
                  if (room.status != RoomConnectionStatus.open) ...[
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
                  const SizedBox(width: AlistenSpacing.sm),
                  _Action(
                    icon: AlistenIcons.playlist,
                    label: '从歌单点歌',
                    onPressed: () => unawaited(
                      context.push<void>('/r/$roomRef/from-playlists'),
                    ),
                  ),
                  const SizedBox(width: AlistenSpacing.md),
                  _Action(
                    icon: AlistenIcons.userPlus,
                    label: '复制邀请链接',
                    onPressed: () =>
                        copyInviteLink(ref, id: room.id, slug: room.slug),
                  ),
                  const SizedBox(width: AlistenSpacing.xs),
                  _Action(
                    icon: AlistenIcons.signOut,
                    label: '退出房间',
                    onPressed: () => unawaited(_leave(context, ref)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AlistenSpacing.md),
              child: LyricsView(
                columnWidth: SettledStageWidth.maybeOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 看起来是输入框，点下去打开点歌页并聚焦到它的输入框。
class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onPressed});

  final VoidCallback onPressed;

  static const _maxWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: '搜歌',
        focusRadius: BorderRadius.circular(AlistenRadii.pill),
        child: Container(
          height: AlistenSizes.iconButton,
          padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.md),
          decoration: BoxDecoration(
            color: colors.raised,
            borderRadius: BorderRadius.circular(AlistenRadii.pill),
            border: Border.all(
              color: colors.glassStroke,
              width: AlistenSizes.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                AlistenIcons.magnifyingGlass,
                size: AlistenSizes.iconSm,
                color: colors.onGlassMuted,
              ),
              const SizedBox(width: AlistenSpacing.xs),
              Expanded(
                child: Text(
                  '搜歌名、歌手，或粘贴链接',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlassMuted,
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

// 只有图标的按钮：名称在悬停提示里，读屏照常读出。
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
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: IconCircleButton(
        icon: icon,
        semanticLabel: label,
        onPressed: onPressed,
      ),
    );
  }
}

/// 中间区域停稳时的宽度。右侧面板展开或收起的途中它不变，歌词照它排一次版，
/// 不必跟着逐帧重排。
class SettledStageWidth extends InheritedWidget {
  const SettledStageWidth({
    required this.width,
    required super.child,
    super.key,
  });

  final double width;

  static double? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettledStageWidth>()?.width;

  @override
  bool updateShouldNotify(SettledStageWidth oldWidget) =>
      width != oldWidget.width;
}

/// 所在房间的队列和聊天，同时显示且可拖动分隔条调整各自高度。离开房间页面时
/// 面板会被移除，所以队列所占的比例 [queueFraction] 由上层保存。
class DesktopRoomPanel extends ConsumerStatefulWidget {
  const DesktopRoomPanel({
    required this.queueFraction,
    required this.onQueueFractionChanged,
    super.key,
  });

  final double queueFraction;
  final ValueChanged<double> onQueueFractionChanged;

  static const defaultQueueFraction = 5 / 9;
  static const splitterHeight = 14.0;
  static const minPaneHeight = 156.0;

  @override
  ConsumerState<DesktopRoomPanel> createState() => _DesktopRoomPanelState();
}

class _DesktopRoomPanelState extends ConsumerState<DesktopRoomPanel> {
  double? _dragStartY;
  double? _dragStartQueueHeight;

  @override
  Widget build(BuildContext context) {
    final toasts = ref.read(toastControllerProvider);
    final router = GoRouter.of(context);
    void openAccount() => router.go('/settings/account');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        0,
        AlistenSpacing.sm,
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
                    child: QueueView(
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
  });

  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragMove;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  @override
  State<_PanelSplitter> createState() => _PanelSplitterState();
}

class _PanelSplitterState extends State<_PanelSplitter> {
  bool _hovered = false;
  bool _dragging = false;

  void _endDrag() {
    widget.onDragEnd();
    if (_dragging) setState(() => _dragging = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final active = _hovered || _dragging;
    final pillAlpha = _dragging
        ? 0.55
        : _hovered
        ? 0.35
        : 0.16;
    return Semantics(
      label: '调整队列与聊天高度',
      hint: '上下拖动调整高度，双击恢复默认比例',
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
                  color: colors.onGlass.withValues(alpha: active ? 0.16 : 0.08),
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
    );
  }
}
