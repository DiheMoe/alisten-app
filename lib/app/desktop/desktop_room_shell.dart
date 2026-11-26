import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show lerpDouble;

import 'package:alisten/app/desktop/desktop_keys.dart';
import 'package:alisten/app/desktop/desktop_room.dart';
import 'package:alisten/app/mini_player.dart';
import 'package:alisten/app/room/room_actions.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/flowing_cover_backdrop.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 右侧面板是否展开、队列占多高。房间的窗口收起再打开是新的一页，这两样要留
/// 在页面之外才不会被重置。
final desktopRoomPanelProvider =
    NotifierProvider<DesktopRoomPanelLayout, ({bool expanded, double queue})>(
      DesktopRoomPanelLayout.new,
    );

final class DesktopRoomPanelLayout
    extends Notifier<({bool expanded, double queue})> {
  @override
  ({bool expanded, double queue}) build() =>
      (expanded: true, queue: DesktopRoomPanel.defaultQueueFraction);

  void setExpanded(bool expanded) =>
      state = (expanded: expanded, queue: state.queue);

  void setQueue(double fraction) =>
      state = (expanded: state.expanded, queue: fraction);
}

/// 房间里的页面由它退出房间：退出会立即清空房间，要先把整个窗口定格。
class DesktopRoomScope extends InheritedWidget {
  const DesktopRoomScope({
    required this.leave,
    required this.window,
    required super.child,
    super.key,
  });

  final VoidCallback leave;

  /// 房间的窗口这一页，里面的内容据此知道它是否正在打开。
  final ModalRoute<Object?>? window;

  static DesktopRoomScope of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DesktopRoomScope>()!;

  @override
  bool updateShouldNotify(DesktopRoomScope oldWidget) => false;
}

/// 桌面窗口里的房间：整窗铺着封面的流动背景，左边是房间的页面，右边同时显示
/// 队列和聊天，并可收起为贴在右边缘的开关。
class DesktopRoomShell extends ConsumerStatefulWidget {
  const DesktopRoomShell({
    required this.location,
    required this.child,
    super.key,
  });

  final Uri location;
  final Widget child;

  static const _minPanelWidth = 300.0;
  static const _maxPanelWidth = 400.0;
  // 窗口再窄，左边放不下歌词，右边的队列和聊天让出位置。
  static const _minStageWidth = 400.0;

  static const _expandCurve = Cubic(0.22, 1.0, 0.36, 1.0);
  static const _collapseCurve = Cubic(0.4, 0.0, 0.2, 1.0);

  @override
  ConsumerState<DesktopRoomShell> createState() => _DesktopRoomShellState();
}

class _DesktopRoomShellState extends ConsumerState<DesktopRoomShell>
    with SingleTickerProviderStateMixin {
  final _page = GlobalKey();
  ui.Image? _still;

  late final AnimationController _panelController = AnimationController(
    vsync: this,
    value: ref.read(desktopRoomPanelProvider).expanded ? 1 : 0,
  );
  late final CurvedAnimation _panelMotion = CurvedAnimation(
    parent: _panelController,
    curve: DesktopRoomShell._expandCurve,
    reverseCurve: DesktopRoomShell._collapseCurve,
  );
  late final CurvedAnimation _panelOpacity = CurvedAnimation(
    parent: _panelController,
    curve: const Interval(0.2, 0.92, curve: Curves.easeOut),
    reverseCurve: const Interval(0.28, 1.0, curve: Curves.easeIn),
  );

  @override
  void dispose() {
    _still?.dispose();
    _panelOpacity.dispose();
    _panelMotion.dispose();
    _panelController.dispose();
    super.dispose();
  }

  void _togglePanel() {
    final expand = !ref.read(desktopRoomPanelProvider).expanded;
    final duration = AlistenDurations.of(context, AlistenDurations.layout);
    ref.read(desktopRoomPanelProvider.notifier).setExpanded(expand);
    if (duration == Duration.zero) {
      _panelController.value = expand ? 1 : 0;
      return;
    }
    _panelController.duration = duration;
    _panelController.reverseDuration = const Duration(milliseconds: 340);
    unawaited(expand ? _panelController.forward() : _panelController.reverse());
  }

  Future<void> _leave() async {
    final router = GoRouter.of(context);
    final room = ref.read(roomControllerProvider.notifier);
    if (!await confirmLeavingRoom(context) || !mounted) return;
    // 退出会立即清空房间，队列、歌词和封面配色都会随之变化。先把窗口换成退出前
    // 最后一帧的画面再离开；等这一帧画完再截取，画面才完整。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final page = _page.currentContext?.findRenderObject();
    if (page is RenderRepaintBoundary) {
      final still = page.toImageSync(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      setState(() => _still = still);
    }
    router.go('/');
    unawaited(room.leaveRoom());
  }

  @override
  Widget build(BuildContext context) {
    if (_still case final still?) {
      return SizedBox.expand(
        child: RawImage(image: still, fit: BoxFit.fill),
      );
    }
    final location = widget.location;
    final child = widget.child;
    final (roomId, joined, cover) = ref.watch(
      roomControllerProvider.select(
        (room) => (
          room.activeRoomId,
          room.snapshot != null,
          room.snapshot?.nowPlaying?.entry.meta.coverUrl,
        ),
      ),
    );
    final layout = ref.watch(desktopRoomPanelProvider);
    final panelExpanded = layout.expanded;
    final segments = location.pathSegments;
    final routeRoom = segments.length >= 2 && segments.first == 'r'
        ? segments[1]
        : null;
    // 还没连上、或正在进入的房间还不是当前房间时，没有队列和聊天可显示。
    final inRoom =
        joined &&
        roomId != null &&
        routeRoom != null &&
        ref.read(roomControllerProvider.notifier).names(routeRoom);
    // 房间的主页面；点歌等页面叠在它上面。
    final onStage = !(segments.length > 2 && _subPages.contains(segments[2]));
    final media = MediaQuery.of(context);
    return DesktopRoomScope(
      leave: () => unawaited(_leave()),
      window: ModalRoute.of(context),
      child: DesktopKeys(
        location: location,
        child: RepaintBoundary(
          key: _page,
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FlowingCoverBackdrop(url: inRoom ? cover : null),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final panelWidth = (constraints.maxWidth * 0.27).clamp(
                      DesktopRoomShell._minPanelWidth,
                      DesktopRoomShell._maxPanelWidth,
                    );
                    final canShowPanel =
                        inRoom &&
                        constraints.maxWidth - panelWidth >=
                            DesktopRoomShell._minStageWidth;
                    // 点歌等页面自己会滚动，滚动条贴着右边缘，开关不压在上面。
                    final showToggle = canShowPanel && onStage;
                    final panel = DesktopRoomPanel(
                      queueFraction: layout.queue,
                      onQueueFractionChanged: ref
                          .read(desktopRoomPanelProvider.notifier)
                          .setQueue,
                    );
                    return AnimatedBuilder(
                      animation: _panelController,
                      child: panel,
                      builder: (context, panelChild) {
                        final progress = canShowPanel
                            ? _panelMotion.value.clamp(0.0, 1.0)
                            : 0.0;
                        final opacity = canShowPanel
                            ? _panelOpacity.value.clamp(0.0, 1.0)
                            : 0.0;
                        final shownWidth = panelWidth * progress;
                        final stageWidth = constraints.maxWidth - shownWidth;
                        final collapsed = progress <= 0.001;
                        // 面板滑动的途中，左边仍按面板展开时的宽度排歌词，停稳后
                        // 才换成新的宽度。
                        final settledStageWidth =
                            constraints.maxWidth -
                            (canShowPanel &&
                                    (panelExpanded ||
                                        _panelController.value > 0)
                                ? panelWidth
                                : 0);
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  // 页面按自己这一块的大小排版，而不是整个窗口。
                                  child: MediaQuery(
                                    data: media.copyWith(
                                      size: Size(
                                        stageWidth,
                                        constraints.maxHeight,
                                      ),
                                    ),
                                    child: ClipRect(
                                      child: SettledStageWidth(
                                        width: settledStageWidth,
                                        // 房间的主页面自带播放控制，点歌等页面
                                        // 下方悬着迷你播放条。
                                        child: MiniPlayerHost(
                                          location: location,
                                          show: !onStage,
                                          insideRoom: true,
                                          child: OverBackdrop(
                                            active: true,
                                            child: child,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (canShowPanel)
                                  SizedBox(
                                    width: shownWidth,
                                    child: TickerMode(
                                      enabled: !collapsed,
                                      child: Offstage(
                                        offstage: collapsed,
                                        child: IgnorePointer(
                                          ignoring: !panelExpanded,
                                          // 收起后 Tab 不应落到看不见的队列和输入框上。
                                          child: ExcludeFocus(
                                            excluding: !panelExpanded,
                                            child: ClipRect(
                                              child: OverflowBox(
                                                alignment: AlignmentDirectional
                                                    .centerStart,
                                                minWidth: panelWidth,
                                                maxWidth: panelWidth,
                                                child: Transform.translate(
                                                  offset: Offset(
                                                    (1 - progress) * 24,
                                                    0,
                                                  ),
                                                  child: Opacity(
                                                    opacity: opacity,
                                                    child: panelChild,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (showToggle)
                              PositionedDirectional(
                                end: shownWidth,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: _PanelEdgeToggle(
                                    expanded: panelExpanded,
                                    progress: progress,
                                    onPressed: _togglePanel,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _subPages = {'search', 'from-playlists', 'playlists'};

class _PanelEdgeToggle extends StatefulWidget {
  const _PanelEdgeToggle({
    required this.expanded,
    required this.progress,
    required this.onPressed,
  });

  final bool expanded;
  final double progress;
  final VoidCallback onPressed;

  @override
  State<_PanelEdgeToggle> createState() => _PanelEdgeToggleState();
}

class _PanelEdgeToggleState extends State<_PanelEdgeToggle> {
  static const _size = Size(16, 48);
  static const _iconSize = 12.0;

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    const radius = Radius.circular(AlistenRadii.sm);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Pressable(
        key: const ValueKey('desktop-panel-toggle'),
        onPressed: widget.onPressed,
        semanticLabel: widget.expanded ? '收起队列与聊天' : '展开队列与聊天',
        expanded: widget.expanded,
        focusRadius: const BorderRadiusDirectional.only(
          topStart: radius,
          bottomStart: radius,
        ).resolve(Directionality.of(context)),
        child: SizedBox.fromSize(
          size: _size,
          child: Center(
            child: Transform.rotate(
              angle: lerpDouble(math.pi, 0.0, widget.progress)!,
              child: Icon(
                AlistenIcons.caretRight,
                size: _iconSize,
                // 平时只是一个很淡的箭头，鼠标指着才醒目。
                color: colors.onGlass.withValues(alpha: _hovered ? 0.8 : 0.3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
