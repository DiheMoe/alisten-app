import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:alisten/app/feedback.dart';
import 'package:alisten/app/layout.dart';
import 'package:alisten/app/room/room_actions.dart';
import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/app/room/room_mode_bar.dart';
import 'package:alisten/app/room/room_pager.dart';
import 'package:alisten/app/room/room_top_bar.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/chat/index.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/flowing_cover_backdrop.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/side_fade.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

typedef _RoomView = ({
  String id,
  String? slug,
  String name,
  int onlineCount,
  int capacity,
  NowPlaying? nowPlaying,
  RoomConnectionStatus status,
  DateTime? nextRetryAt,
  bool mayReconnectNow,
});

_RoomView? _viewOf(RoomState room) {
  final snapshot = room.snapshot;
  final id = room.activeRoomId;
  if (snapshot == null || id == null) return null;
  return (
    id: id,
    slug: room.roomSlug,
    name: snapshot.room.name,
    onlineCount: snapshot.onlineCount,
    capacity: snapshot.room.capacity,
    nowPlaying: snapshot.nowPlaying,
    status: room.status,
    nextRetryAt: room.nextRetryAt,
    mayReconnectNow: room.mayReconnectNow,
  );
}

/// 只经由 `RoomRouteGate` 显示：此时 [roomRef] 指向活动房间，
/// 且房间快照已经到达。
class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({required this.roomRef, required this.mode, super.key});

  final String roomRef;
  final RoomMode mode;

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  // 房间已退出、页面仍在滑出时继续显示最后的房间，以免页面变成空白。
  _RoomView? _shown;

  // 切回播放器时保留上一个模式，内容按原样淡出；横屏两栏右栏也共用它（默认歌词）。
  late RoomMode _pane = _paneFor(widget.mode, RoomMode.lyrics);

  // 播放器在手机布局和两栏布局之间移动时保留状态（投票、封面位置动画），
  // 旋转或展开折叠屏不会让它从头开始。
  final _player = GlobalKey();

  final _page = GlobalKey();

  final _phonePages = GlobalKey<RoomPagerState>();
  final _landscapeSidePages = GlobalKey<RoomPagerState>();
  final _phonePosition = ValueNotifier(0.0);
  final _landscapePosition = ValueNotifier(0.0);

  ui.Image? _still;

  static RoomMode _paneFor(RoomMode mode, RoomMode previous) =>
      mode == RoomMode.player ? previous : mode;

  @override
  void didUpdateWidget(RoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pane = _paneFor(widget.mode, _pane);
  }

  @override
  void dispose() {
    _phonePosition.dispose();
    _landscapePosition.dispose();
    _still?.dispose();
    super.dispose();
  }

  void _show(RoomMode mode) => context.go(mode.routeIn(widget.roomRef));

  // 从播放器选标签时直接显示该页，不从正在淡出的上一个模式滑过去。
  void _choosePhone(RoomMode mode) {
    if (widget.mode != RoomMode.player) {
      _phonePages.currentState?.glideTo(mode);
    }
    _show(mode);
  }

  void _chooseSide(RoomMode mode) {
    _landscapeSidePages.currentState?.glideTo(mode);
    _show(mode);
  }

  // 回弹停稳之前用户可能已经收起房间、返回或去了别处，停稳的页不能把路由改回来。
  bool get _routeUnchanged =>
      GoRouter.of(context).state.uri.path ==
      widget.mode.routeIn(widget.roomRef);

  void _settlePhone(RoomMode mode) {
    // 展开播放器后，内容随之淡出。
    if (widget.mode != RoomMode.player && _routeUnchanged) _show(mode);
  }

  void _settleSide(RoomMode mode) {
    if (_routeUnchanged) _show(mode);
  }

  void _searchSongs() =>
      unawaited(context.push<void>('/r/${widget.roomRef}/search'));

  void _pickFromPlaylists() =>
      unawaited(context.push<void>('/r/${widget.roomRef}/from-playlists'));

  Future<void> _leave() async {
    final confirmed = await confirmLeavingRoom(context);
    if (!confirmed || !mounted) return;
    final room = ref.read(roomControllerProvider.notifier);
    // 退出会立即清空房间，队列、歌词、进度和封面配色都会随之变化。
    // 因此先把页面换成退出前最后一帧的截图再滑出；
    // 等这一帧画完再截取，画面才完整。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final page = _page.currentContext?.findRenderObject();
    if (page is RenderRepaintBoundary) {
      final still = page.toImageSync(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      setState(() => _still = still);
    }
    context.go('/');
    unawaited(room.leaveRoom());
  }

  @override
  Widget build(BuildContext context) {
    if (_still case final still?) {
      return SizedBox.expand(
        child: RawImage(image: still, fit: BoxFit.fill),
      );
    }
    final room = _shown =
        ref.watch(roomControllerProvider.select(_viewOf)) ?? _shown;
    if (room == null) return const SizedBox.shrink();
    final nowPlaying = room.nowPlaying;
    final mode = widget.mode;
    final layout = roomLayoutOf(context);
    final wide = layout != RoomLayout.compact;
    final toasts = ref.read(toastControllerProvider);
    void reportQueue(MutationResult<Object?> result, String success) =>
        reportMutation(toasts, result, success: (_) => success);
    void copyTitle(String title) => copySongTitle(toasts, title);
    // 面板在根导航器上，换到另一个房间时它仍开着，这个页面却可能已被换下。
    final router = GoRouter.of(context);
    void openAccount() => router.go('/settings/account');
    void saveToPlaylist(BuildContext context, Track track, String title) =>
        unawaited(
          showSaveToPlaylistSheet(
            context,
            SaveOneTrack(track: track, title: title),
            onOpenAccount: openAccount,
            onNotice: toasts.show,
          ),
        );
    Widget content(RoomMode page) => switch (page) {
      RoomMode.lyrics || RoomMode.player => const LyricsView(),
      RoomMode.queue => QueueView(
        onResult: reportQueue,
        onCopyTitle: copyTitle,
        onSaveToPlaylist: saveToPlaylist,
      ),
      RoomMode.chat => const ChatView(),
    };
    final background = FlowingCoverBackdrop(
      url: nowPlaying?.entry.meta.coverUrl,
    );
    final topBar = RoomTopBar(
      name: room.name,
      onlineCount: room.onlineCount,
      capacity: room.capacity,
      status: room.status,
      nextRetryAt: room.nextRetryAt,
      onCollapse: () => context.go('/'),
      onInvite: () => copyInviteLink(ref, id: room.id, slug: room.slug),
      onLeave: () => unawaited(_leave()),
      onRetryNow: room.mayReconnectNow
          ? () => unawaited(
              ref.read(roomControllerProvider.notifier).checkConnection(),
            )
          : null,
    );
    final player = NowPlayingHeader(
      key: _player,
      nowPlaying: nowPlaying,
      compact: !wide && mode != RoomMode.player,
      connected: room.status == RoomConnectionStatus.open,
      onVoteSkipped: (result) => reportVote(toasts, result),
      onExpand: () => _show(RoomMode.player),
      onCopyTitle: copyTitle,
      saveToPlaylist: (track, title) => SaveToPlaylistButton(
        track: track,
        title: title,
        onOpenAccount: openAccount,
        onNotice: toasts.show,
      ),
      body: wide
          ? null
          : RoomPager(
              key: _phonePages,
              pages: RoomModeBar.modes,
              page: _pane,
              position: _phonePosition,
              onSettled: _settlePhone,
              builder: content,
            ),
    );
    final Widget body = switch (layout) {
      RoomLayout.compact => player,
      RoomLayout.landscapeTwoPanes => _LandscapeTwoPanes(
        player: player,
        side: _LandscapeSide(
          bar: RoomModeBar(
            mode: _pane,
            position: _landscapePosition,
            // 播放器一直在左边：再点一次选中的那格，内容不用收起。
            onSelect: (next) {
              if (next != RoomMode.player) _chooseSide(next);
            },
            onSearch: _searchSongs,
            onPickFromPlaylists: _pickFromPlaylists,
            padding: const EdgeInsets.only(bottom: AlistenSpacing.sm),
          ),
          position: _landscapePosition,
          pages: RoomPager(
            key: _landscapeSidePages,
            pages: RoomModeBar.modes,
            page: _pane,
            position: _landscapePosition,
            onSettled: _settleSide,
            builder: (mode) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _landscapeContentWidth,
                ),
                child: content(mode),
              ),
            ),
          ),
        ),
      ),
    };
    return RepaintBoundary(
      key: _page,
      child: QueueCoverWarmup(
        child: AlistenScaffold(
          background: background,
          topBar: topBar,
          contentMaxWidth: wide
              ? double.infinity
              : AlistenSizes.contentMaxWidth,
          // 两栏时键盘只推高右栏，由两栏布局自行处理。
          resizeToAvoidBottomInset: !wide,
          body: body,
          bottomBar: wide
              ? null
              : RoomModeBar(
                  mode: mode,
                  position: _phonePosition,
                  onSelect: _choosePhone,
                  onSearch: _searchSongs,
                  onPickFromPlaylists: _pickFromPlaylists,
                ),
        ),
      ),
    );
  }
}

const _minLandscapePlayerWidth = 320.0;
const _maxLandscapePlayerWidth = 520.0;
const _landscapeMaxStageWidth = 1200.0;
// 横屏右栏较宽：模式条收在手机屏幕那么宽，内容收在读起来不费眼的宽度，都居中。
const _landscapeBarWidth = 400.0;
const _landscapeContentWidth = 560.0;

class _LandscapeTwoPanes extends StatelessWidget {
  const _LandscapeTwoPanes({required this.player, required this.side});

  final Widget player;
  final Widget side;

  @override
  Widget build(BuildContext context) {
    // 左栏固定放完整播放器，键盘升降时不移动；右栏放歌词/队列/聊天，随键盘上移。
    final system = MediaQuery.viewPaddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        system.left + AlistenSpacing.page,
        AlistenSpacing.xs,
        system.right + AlistenSpacing.page,
        0,
      ),
      child: MediaQuery(
        data: MediaQuery.of(context)
            .removePadding(
              removeLeft: true,
              removeRight: true,
              removeBottom: true,
            )
            .removeViewInsets(removeBottom: true),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _landscapeMaxStageWidth,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = AlistenSpacing.lg;
                final playerWidth = ((constraints.maxWidth - gap) * 0.45).clamp(
                  _minLandscapePlayerWidth,
                  _maxLandscapePlayerWidth,
                );
                final playerBottom = system.bottom + AlistenSpacing.page;
                // 右栏的顶边对齐封面的顶边，底边对齐播放按钮的底边。
                final stage = NowPlayingHeader.stageInsets(
                  context,
                  Size(playerWidth, constraints.maxHeight - playerBottom),
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: playerWidth,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: playerBottom),
                        child: player,
                      ),
                    ),
                    const SizedBox(width: gap),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: stage.top,
                          bottom: math.max(
                            playerBottom + stage.bottom,
                            keyboard + AlistenSpacing.page,
                          ),
                        ),
                        child: side,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LandscapeSide extends StatelessWidget {
  const _LandscapeSide({
    required this.bar,
    required this.position,
    required this.pages,
  });

  final Widget bar;
  final ValueListenable<double> position;
  final Widget pages;

  @override
  Widget build(BuildContext context) {
    final barHeight =
        PillButton.heightOf(context, large: true) + AlistenSpacing.sm;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 矮屏上键盘升起时右栏可能很矮：内容（如正在使用的输入框）仍至少有
          // 模式条那么高时才显示模式条。
          if (constraints.maxHeight >= 2 * barHeight)
            Center(
              key: const ValueKey('switch'),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.textScalerOf(context)
                      .scale(_landscapeBarWidth),
                ),
                child: bar,
              ),
            ),
          // 模式条出现或消失时聊天保留状态，输入框不失去焦点。
          Expanded(
            key: const ValueKey('body'),
            // 手机上内容滑出屏幕；这里左边紧挨着播放器，滑出去的内容渐隐。
            child: SideFade(
              position: position,
              extent: AlistenSpacing.lg,
              child: pages,
            ),
          ),
        ],
      ),
    );
  }
}
