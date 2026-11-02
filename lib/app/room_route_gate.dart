import 'dart:async';

import 'package:alisten/app/room/connection_pill.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/lobby/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final roomEntryProvider = AsyncNotifierProvider.autoDispose
    .family<RoomEntry, RoomJoin, String>(
      RoomEntry.new,
      // 进入的结果会显示给用户，只由用户手动重试。
      retry: (_, _) => null,
    );

/// 房间尚未进入时，一旦没有页面再显示该请求就撤回它，
/// 从房间页返回不会替换正在播放的房间。只撤回这一个请求，
/// 其他调用方对同一房间的请求继续进行。
final class RoomEntry extends AsyncNotifier<RoomJoin> {
  RoomEntry(this.roomRef);

  final String roomRef;
  final _pages = <Object>{};
  void Function() _withdraw = _nothing;

  @override
  Future<RoomJoin> build() {
    final room = ref.read(roomControllerProvider.notifier);
    final opening = room.beginOpen(roomRef);
    _withdraw = () => room.cancelOpen(opening.attempt);
    // provider 销毁时页面都已不在，即使它们没有调用 [hide] 也要撤回。
    ref.onDispose(_withdraw);
    return opening.result;
  }

  void show(Object page) => _pages.add(page);

  void hide(Object page) {
    if (_pages.remove(page) && _pages.isEmpty) _withdraw();
  }

  static void _nothing() {}
}

/// 房间路由下的每个页面都经过它，不会在一个房间的路由下显示另一个房间。
class RoomRouteGate extends ConsumerStatefulWidget {
  const RoomRouteGate({required this.roomRef, required this.child, super.key});

  final String roomRef;
  final Widget child;

  @override
  ConsumerState<RoomRouteGate> createState() => _RoomRouteGateState();
}

final class _RoomRouteGateState extends ConsumerState<RoomRouteGate> {
  ModalRoute<Object?>? _page;
  Animation<double>? _route;
  RoomEntry? _entry;
  bool _left = false;
  Widget? _shown;

  // 页面开始离开时的内容。离开可能清空房间或让请求有了结果，不保留的话页面会在
  // 滑出途中变成别的内容。
  Widget? _leaving;

  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void didUpdateWidget(RoomRouteGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomRef == widget.roomRef) return;
    final previous = _entry;
    _show();
    previous?.hide(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _page = ModalRoute.of(context);
    final animation = _page?.animation;
    if (animation == _route) return;
    _route?.removeStatusListener(_routeChanged);
    _route = animation?..addStatusListener(_routeChanged);
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_routeChanged);
    super.dispose();
  }

  // 只读取一次请求：请求销毁后再读取会为这个房间发起新的请求。
  void _show() {
    final entry = ref.read(roomEntryProvider(widget.roomRef).notifier);
    entry.show(this);
    _entry = entry;
  }

  // 页面一开始离开就撤回尚未答复的请求，因为答复可能在滑出途中到达。
  // 此后页面保持当时显示的内容。
  void _routeChanged(AnimationStatus status) {
    final leaving = switch (status) {
      AnimationStatus.reverse => true,
      // 返回手势拖到底后松手仍可取消，页面会留下。
      AnimationStatus.dismissed => !(_page?.isActive ?? false),
      AnimationStatus.forward || AnimationStatus.completed => false,
    };
    if (_left || !leaving) return;
    _left = true;
    _leaving ??= _shown ?? widget.child;
    _entry?.hide(this);
  }

  @override
  Widget build(BuildContext context) {
    final frozen = _leaving;
    if (frozen != null) return frozen;
    final roomRef = widget.roomRef;
    final room = ref.watch(roomControllerProvider);
    final entry = ref.watch(roomEntryProvider(roomRef));
    final current = ref.read(roomControllerProvider.notifier).names(roomRef);
    final failure = room.failure;
    final listing = switch (entry.value) {
      RoomJoined(room: final joined) => joined,
      RoomJoinFailed(room: final refused) => refused,
      null => null,
    };
    final Widget body;
    if (!current) {
      // 重新进入期间仍显示上一次的原因，只有按钮转圈。
      body = switch (entry) {
        AsyncValue(hasError: true) => _Refusal(
          roomRef: roomRef,
          listing: listing,
          failure: RoomFailure.unavailable,
          message: '无法进入房间，请检查网络后重试。',
          alive: true,
          onLeaving: _freeze,
        ),
        AsyncValue(value: RoomJoinFailed(:final failure, :final message)) =>
          _Refusal(
            roomRef: roomRef,
            listing: listing,
            failure: failure,
            message: message,
            alive: true,
            onLeaving: _freeze,
          ),
        AsyncValue(hasValue: true) => _Refusal(
          roomRef: roomRef,
          listing: listing,
          failure: RoomFailure.unavailable,
          message: '已经切换到其他房间。',
          alive: true,
          onLeaving: _freeze,
        ),
        AsyncValue() => const _Busy(label: '正在进入房间'),
      };
    } else if (failure != null) {
      body = _Refusal(
        roomRef: roomRef,
        listing: listing,
        failure: failure,
        message: room.errorMessage ?? '无法进入房间。',
        alive: false,
        onLeaving: _freeze,
      );
    } else if (room.snapshot == null) {
      // 首次连接失败后一直停在等待重连页，倒计时结束和重连期间也不切换内容，
      // 由状态胶囊区分两者。
      body = room.status == RoomConnectionStatus.reconnecting
          ? _WaitingToReconnect(room: room)
          : const _Busy(label: '正在连接房间');
    } else {
      _shown = null;
      return widget.child;
    }
    return _shown = AlistenScaffold(
      topBar: AlistenTopBar(
        leading: IconCircleButton(
          icon: Icons.arrow_back_rounded,
          semanticLabel: '返回',
          style: IconCircleButtonStyle.plain,
          onPressed: () => _back(context),
        ),
      ),
      body: Semantics(liveRegion: true, child: body),
    );
  }

  void _freeze() => _leaving = _shown;
}

void _back(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}

final class _Busy extends StatelessWidget {
  const _Busy({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AlistenSpacing.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BusyIndicator(size: AlistenSizes.iconLg),
            const SizedBox(height: AlistenSpacing.md),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AlistenTypography.bodyStrong.copyWith(
                color: colors.onGlass,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _WaitingToReconnect extends ConsumerWidget {
  const _WaitingToReconnect({required this.room});

  final RoomState room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      title: '暂时连不上房间',
      message: '没有连上房间，会自动重试。',
      action: ConnectionPill(
        status: room.status,
        nextRetryAt: room.nextRetryAt,
        onRetryNow: room.mayReconnectNow
            ? () => unawaited(
                ref.read(roomControllerProvider.notifier).checkConnection(),
              )
            : null,
      ),
    );
  }
}

final class _Refusal extends ConsumerWidget {
  const _Refusal({
    required this.roomRef,
    required this.listing,
    required this.failure,
    required this.message,
    required this.alive,
    required this.onLeaving,
  });

  final String roomRef;

  final RoomListing? listing;
  final RoomFailure failure;
  final String message;

  // 为 true 时失败的只是这次进入，活动房间（如果有）照常运行；
  // 返回大厅时只退出失败的房间。
  final bool alive;

  // 用户返回大厅时、退出房间之前调用。
  final VoidCallback onLeaving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, title) = switch (failure) {
      RoomFailure.authorization => (Icons.lock_rounded, '需要验证才能进入'),
      RoomFailure.notFound => (Icons.search_off_rounded, '找不到这个房间'),
      RoomFailure.outdated => (Icons.system_update_rounded, '需要更新 Alisten'),
      RoomFailure.unavailable => (Icons.cloud_off_rounded, '暂时进不了房间'),
    };
    final retrying = ref.watch(roomEntryProvider(roomRef)).isLoading;
    final enterAgain = PillButton(
      label: '重新进入',
      icon: Icons.refresh_rounded,
      busy: retrying,
      onPressed: () => ref.invalidate(roomEntryProvider(roomRef)),
    );
    final listing = this.listing;
    final again = switch (failure) {
      // 没有密码的房间（如票据过期、身份被替换）重新进入即可，不需要面板。
      RoomFailure.authorization when listing != null && !listing.hasPassword =>
        enterAgain,
      RoomFailure.authorization => PillButton(
        label: '输入密码',
        icon: Icons.key_rounded,
        onPressed: () => unawaited(
          showJoinRoomSheet(context, ref, roomRef: roomRef, room: listing),
        ),
      ),
      RoomFailure.unavailable => enterAgain,
      RoomFailure.notFound || RoomFailure.outdated => null,
    };
    return EmptyState(
      icon: icon,
      title: title,
      message: message,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (again != null) ...[
            again,
            const SizedBox(height: AlistenSpacing.xs),
          ],
          PillButton(
            label: '返回大厅',
            style: again == null
                ? PillButtonStyle.secondary
                : PillButtonStyle.ghost,
            onPressed: () => _toLobby(context, ref),
          ),
        ],
      ),
    );
  }

  void _toLobby(BuildContext context, WidgetRef ref) {
    final room = ref.read(roomControllerProvider.notifier);
    onLeaving();
    if (!alive) unawaited(room.leaveRoom());
    context.go('/');
  }
}
