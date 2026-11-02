import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/app/feedback.dart';
import 'package:alisten/app/layout.dart';
import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/app/room/room_mode_bar.dart';
import 'package:alisten/app/room/room_top_bar.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/chat/index.dart';
import 'package:alisten/features/lyrics/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/aurora_background.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/cover_backdrop.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/segmented_pills.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

typedef _RoomView = ({
  String id,
  String? slug,
  String name,
  int onlineCount,
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

  // 切回播放器时保留上一个模式，内容按原样淡出。
  late RoomMode _pane = _paneFor(widget.mode, RoomMode.lyrics);

  late RoomMode _side = _sideFor(widget.mode, RoomMode.queue);

  // 播放器在手机布局和两栏布局之间移动时保留状态（投票、封面位置动画），
  // 旋转或展开折叠屏不会让它从头开始。
  final _player = GlobalKey();

  final _page = GlobalKey();

  ui.Image? _still;

  static RoomMode _paneFor(RoomMode mode, RoomMode previous) =>
      mode == RoomMode.player ? previous : mode;

  static RoomMode _sideFor(RoomMode mode, RoomMode previous) =>
      mode == RoomMode.queue || mode == RoomMode.chat ? mode : previous;

  @override
  void didUpdateWidget(RoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pane = _paneFor(widget.mode, _pane);
    _side = _sideFor(widget.mode, _side);
  }

  @override
  void dispose() {
    _still?.dispose();
    super.dispose();
  }

  void _show(RoomMode mode) => context.go(mode.routeIn(widget.roomRef));

  void _addSong() =>
      unawaited(context.push<void>('/r/${widget.roomRef}/search'));

  void _invite(_RoomView room) {
    final link = ref
        .read(deepLinkControllerProvider)
        .inviteLink(id: room.id, slug: room.slug);
    unawaited(Clipboard.setData(ClipboardData(text: link)));
    ref.read(toastControllerProvider).show(ToastKind.success, '邀请链接已复制');
  }

  Future<void> _leave() async {
    final confirmed = await showConfirmSheet(
      context,
      title: '退出这个房间？',
      message: '这台设备会停止播放，房间里的其他人照常收听。',
      confirmLabel: '退出房间',
      confirmIcon: Icons.logout_rounded,
      // 面板收起后页面才能以动画滑出。
      untilClosed: true,
    );
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

  static void _reportVote(
    ToastController toasts,
    MutationResult<VoteSkipResult> result,
  ) {
    reportMutation(
      toasts,
      result,
      success: (vote) =>
          vote.skipped ? '已切歌' : '已投票 ${vote.votes}/${vote.requiredVotes}',
    );
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
    final twoPanes = roomInTwoPanes(context);
    final toasts = ref.read(toastControllerProvider);
    void reportQueue(MutationResult<Object?> result, String success) =>
        reportMutation(toasts, result, success: (_) => success);
    final background = CoverBackdrop(
      url: nowPlaying?.entry.meta.coverUrl,
      child: const AuroraBackground(),
    );
    final topBar = RoomTopBar(
      name: room.name,
      onlineCount: room.onlineCount,
      status: room.status,
      nextRetryAt: room.nextRetryAt,
      onCollapse: () => context.go('/'),
      onInvite: () => _invite(room),
      onLeave: () => unawaited(_leave()),
      onRetryNow: room.mayReconnectNow
          ? () => unawaited(
              ref.read(roomControllerProvider.notifier).checkConnection(),
            )
          : null,
      onAddSong: twoPanes ? _addSong : null,
    );
    final player = NowPlayingHeader(
      key: _player,
      nowPlaying: nowPlaying,
      compact: !twoPanes && mode != RoomMode.player,
      connected: room.status == RoomConnectionStatus.open,
      onAddSong: _addSong,
      onVoteSkipped: (result) => _reportVote(toasts, result),
      onExpand: () => _show(RoomMode.player),
      body: twoPanes
          ? null
          : _ModeBody(
              mode: _pane,
              onAddSong: _addSong,
              onQueueResult: reportQueue,
            ),
    );
    return RepaintBoundary(
      key: _page,
      child: AlistenScaffold(
        background: background,
        topBar: topBar,
        contentMaxWidth: twoPanes
            ? double.infinity
            : AlistenSizes.contentMaxWidth,
        // 两栏时键盘只推高右栏，由 `_TwoPanes` 处理。
        resizeToAvoidBottomInset: !twoPanes,
        body: twoPanes
            ? _TwoPanes(
                player: player,
                side: _SidePanel(
                  mode: _side,
                  onSelect: _show,
                  onAddSong: _addSong,
                  onQueueResult: reportQueue,
                ),
              )
            : player,
        bottomBar: twoPanes
            ? null
            : RoomModeBar(mode: mode, onSelect: _show, onAddSong: _addSong),
      ),
    );
  }
}

class _TwoPanes extends StatelessWidget {
  const _TwoPanes({required this.player, required this.side});

  final Widget player;
  final Widget side;

  @override
  Widget build(BuildContext context) {
    // 左栏按不随键盘变化的系统边距排版，键盘升降时播放器和歌词不重排；
    // 只有右栏让到键盘之上。
    final system = MediaQuery.viewPaddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        system.left,
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: system.bottom + AlistenSpacing.page,
                ),
                child: Column(
                  children: [
                    Expanded(child: player),
                    const Expanded(child: LyricsView()),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: AlistenSizes.sidePanelWidth,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom:
                      math.max(system.bottom, keyboard) + AlistenSpacing.page,
                ),
                child: side,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.mode,
    required this.onSelect,
    required this.onAddSong,
    required this.onQueueResult,
  });

  // 只会是 [RoomMode.queue] 或 [RoomMode.chat]。
  final RoomMode mode;
  final ValueChanged<RoomMode> onSelect;
  final VoidCallback onAddSong;
  final QueueResultCallback onQueueResult;

  @override
  Widget build(BuildContext context) {
    final switcher = Padding(
      key: const ValueKey('switch'),
      padding: const EdgeInsets.all(AlistenSpacing.sm),
      child: SegmentedPills(
        segments: const [
          PillSegment(
            value: RoomMode.queue,
            label: '队列',
            icon: Icons.queue_music_rounded,
          ),
          PillSegment(
            value: RoomMode.chat,
            label: '聊天',
            icon: Icons.forum_rounded,
          ),
        ],
        selected: mode,
        onChanged: onSelect,
      ),
    );
    final switcherHeight =
        SegmentedPills.heightOf(context) + 2 * AlistenSpacing.sm;
    return GlassPanel(
      padding: EdgeInsets.zero,
      radius: AlistenRadii.lg,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 矮屏上键盘升起时右栏可能很矮：显示切换行之后，
            // 队列或聊天（如正在使用的输入框）仍至少有切换行那么高时才显示它。
            if (constraints.maxHeight >= 2 * switcherHeight) switcher,
            // 切换行出现或消失时聊天保留状态，输入框不失去焦点。
            Expanded(
              key: const ValueKey('body'),
              child: _ModeBody(
                mode: mode,
                onAddSong: onAddSong,
                onQueueResult: onQueueResult,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeBody extends StatelessWidget {
  const _ModeBody({
    required this.mode,
    required this.onAddSong,
    required this.onQueueResult,
  });

  final RoomMode mode;
  final VoidCallback onAddSong;
  final QueueResultCallback onQueueResult;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AlistenDurations.of(context, AlistenDurations.medium),
      switchInCurve: AlistenCurves.standard,
      switchOutCurve: AlistenCurves.exit,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: KeyedSubtree(
        key: ValueKey(mode),
        child: switch (mode) {
          RoomMode.lyrics || RoomMode.player => const LyricsView(),
          RoomMode.queue => QueueView(
            onAddSong: onAddSong,
            onResult: onQueueResult,
          ),
          RoomMode.chat => const ChatView(),
        },
      ),
    );
  }
}
