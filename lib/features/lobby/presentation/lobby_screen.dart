import 'dart:async';

import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/lobby/application/lobby_controller.dart';
import 'package:alisten/features/lobby/presentation/create_room_sheet.dart';
import 'package:alisten/features/lobby/presentation/join_room_sheet.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/avatar_images.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/collapsible.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/cover_backdrop.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/page_glow.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/pull_refresh.dart';
import 'package:alisten/shared/ui/section_header.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _createSpace = AlistenSizes.largeTouchTarget + 2 * AlistenSpacing.md;

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({
    required this.onOpenRoom,
    required this.onOpenHistory,
    required this.onOpenSettings,
    required this.onNotice,
    super.key,
  });

  /// 参数是房间别名或 UUID。
  final ValueChanged<String> onOpenRoom;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenSettings;
  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  late final TextEditingController _filter;
  final _filterFocus = FocusNode(debugLabel: 'lobby filter');
  late final AppLifecycleListener _lifecycle;

  late bool _filtering;
  String? _joining;
  bool _joinSheetShown = false;
  bool _pulling = false;

  LobbyController get _lobby => ref.read(lobbyControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    final query = ref.read(lobbyControllerProvider).query;
    _filter = TextEditingController(text: query);
    _filtering = query.isNotEmpty;
    _filterFocus.addListener(_onFilterFocus);
    _lifecycle = AppLifecycleListener(onHide: _releaseFocus);
    // 构建期间不能改 provider 状态。
    unawaited(
      Future.microtask(() async {
        if (mounted) await _lobby.load();
      }),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _filterFocus.dispose();
    _filter.dispose();
    super.dispose();
  }

  // 面板关闭后框架会把焦点还给输入框，回到前台时仍有焦点的输入框会再次弹出
  // 键盘，所以打开面板和进入后台前先放下焦点。离开大厅时由路由统一处理。
  void _releaseFocus() => _filterFocus.unfocus();

  void _onFilterFocus() {
    if (!mounted) return;
    if (!_filterFocus.hasFocus && _filter.text.isEmpty && _filtering) {
      setState(() => _filtering = false);
    }
  }

  void _startFiltering() {
    setState(() => _filtering = true);
    _filterFocus.requestFocus();
  }

  void _open(RoomListing room) => widget.onOpenRoom(room.slug ?? room.id);

  Future<void> _join(RoomListing room) async {
    if (room.hasPassword) return _showJoin(room);
    setState(() => _joining = room.id);
    try {
      final joined = await _lobby.join(room.id);
      if (mounted) _open(joined);
    } on LobbyActionException catch (error) {
      if (mounted) {
        widget.onNotice(
          error.unknown ? ToastKind.warning : ToastKind.failure,
          error.message,
        );
      }
    } finally {
      if (mounted) setState(() => _joining = null);
    }
  }

  Future<void> _showJoin(RoomListing room) async {
    if (_joinSheetShown) return;
    _releaseFocus();
    setState(() {
      _joinSheetShown = true;
      _joining = room.id;
    });
    try {
      final joined = await showJoinRoomSheet(
        context,
        ref,
        roomRef: room.id,
        room: room,
        onChecked: () {
          if (mounted) setState(() => _joining = null);
        },
      );
      if (joined != null && mounted) _open(joined);
    } finally {
      if (mounted) {
        setState(() {
          _joinSheetShown = false;
          _joining = null;
        });
      }
    }
  }

  Future<void> _showCreate() async {
    _releaseFocus();
    final room = await showCreateRoomSheet(context);
    if (room != null && mounted) _open(room);
  }

  void _clearFilter() {
    _filter.clear();
    _lobby.filter('');
    setState(() => _filtering = _filterFocus.hasFocus);
  }

  Future<void> _pullRefresh() async {
    setState(() => _pulling = true);
    try {
      await _lobby.load();
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lobby = ref.watch(lobbyControllerProvider);
    final avatarUrl = ref.watch(
      identityControllerProvider.select(
        (state) => state.member?.avatarUrl(AlistenSizes.avatar),
      ),
    );
    // 必须在 scaffold 之外读取：scaffold 会从页面中去掉键盘高度。
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final listError = lobby.listError;
    final busy = lobby.busy || _joinSheetShown;
    final loading = lobby.loading && !_pulling;
    return AlistenScaffold(
      background: const PageGlow(),
      body: Builder(
        builder: (context) {
          // 已包含悬浮在安全区之上的迷你播放条。
          final bottom = MediaQuery.paddingOf(context).bottom;
          return Stack(
            children: [
              CustomScrollView(
                physics: pullRefreshPhysics(context),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _LobbyHeader(
                      topInset: MediaQuery.paddingOf(context).top,
                      scaler: MediaQuery.textScalerOf(context),
                      barExtent: PillButton.heightOf(context),
                      actions: [
                        IconCircleButton(
                          icon: Icons.history_rounded,
                          semanticLabel: '播放历史',
                          style: IconCircleButtonStyle.plain,
                          onPressed: widget.onOpenHistory,
                        ),
                        IconCircleButton(
                          icon: Icons.settings_rounded,
                          semanticLabel: '设置',
                          style: IconCircleButtonStyle.plain,
                          image: avatarUrl == null
                              ? null
                              : AvatarImages.of(context, avatarUrl),
                          onPressed: widget.onOpenSettings,
                        ),
                      ],
                    ),
                  ),
                  SliverPullRefresh(onRefresh: _pullRefresh),
                  _ContinueListening(onOpen: widget.onOpenRoom),
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      '房间',
                      padding: const EdgeInsets.fromLTRB(
                        AlistenSpacing.page,
                        AlistenSpacing.md,
                        AlistenSpacing.page,
                        AlistenSpacing.xs,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_filtering && lobby.rooms.isNotEmpty)
                            IconCircleButton(
                              icon: Icons.search_rounded,
                              semanticLabel: '筛选房间',
                              style: IconCircleButtonStyle.plain,
                              onPressed: _startFiltering,
                            ),
                          if (loading)
                            const SizedBox.square(
                              dimension: AlistenSizes.minTouchTarget,
                              child: Center(
                                child: BusyIndicator(
                                  size: AlistenSizes.iconSm,
                                  semanticLabel: '正在刷新房间列表',
                                ),
                              ),
                            )
                          else
                            IconCircleButton(
                              icon: Icons.refresh_rounded,
                              semanticLabel: '刷新房间列表',
                              style: IconCircleButtonStyle.plain,
                              onPressed: () => unawaited(_lobby.load()),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _filterField()),
                  if (listError != null && lobby.rooms.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AlistenSpacing.page,
                        0,
                        AlistenSpacing.page,
                        AlistenSpacing.sm,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: InlineMessage(
                          text: listError,
                          action: PillButton(
                            label: '重试',
                            style: PillButtonStyle.ghost,
                            onPressed: lobby.loading
                                ? null
                                : () => unawaited(_lobby.load()),
                          ),
                        ),
                      ),
                    ),
                  ..._rooms(lobby, loading, bottom + _createSpace),
                ],
              ),
              if (!typing)
                PositionedDirectional(
                  end: AlistenSpacing.page,
                  bottom: bottom + AlistenSpacing.md,
                  child: PillButton(
                    label: '创建房间',
                    icon: Icons.add_rounded,
                    large: true,
                    glow: true,
                    onPressed: busy ? null : () => unawaited(_showCreate()),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _filterField() {
    return Collapsible(
      open: _filtering,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AlistenSpacing.page,
          0,
          AlistenSpacing.page,
          AlistenSpacing.sm,
        ),
        child: AlistenTextField(
          controller: _filter,
          focusNode: _filterFocus,
          hint: '筛选房间',
          icon: Icons.search_rounded,
          pill: true,
          textInputAction: TextInputAction.search,
          onChanged: _lobby.filter,
          onClear: () => _lobby.filter(''),
          onTapOutside: (_) => _releaseFocus(),
        ),
      ),
    );
  }

  List<Widget> _rooms(LobbyState lobby, bool loading, double bottom) {
    Widget fill(Widget child) {
      return SliverFillRemaining(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: child,
        ),
      );
    }

    final error = lobby.listError;
    if (lobby.rooms.isEmpty) {
      if (loading) {
        return [
          fill(
            const Center(
              child: BusyIndicator(
                size: AlistenSizes.iconLg,
                semanticLabel: '正在加载房间',
              ),
            ),
          ),
        ];
      }
      return [
        fill(
          error != null
              ? Semantics(
                  liveRegion: true,
                  child: EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: error,
                    action: PillButton(
                      label: '重试',
                      icon: Icons.refresh_rounded,
                      style: PillButtonStyle.secondary,
                      onPressed: () => unawaited(_lobby.load()),
                    ),
                  ),
                )
              : EmptyState(
                  icon: Icons.meeting_room_rounded,
                  title: '还没有可加入的房间',
                  message: '创建一个房间，邀请朋友一起听。',
                  action: PillButton(
                    label: '刷新',
                    icon: Icons.refresh_rounded,
                    style: PillButtonStyle.secondary,
                    onPressed: () => unawaited(_lobby.load()),
                  ),
                ),
        ),
      ];
    }
    final rooms = lobby.filteredRooms;
    if (rooms.isEmpty) {
      return [
        fill(
          EmptyState(
            icon: Icons.search_off_rounded,
            title: '没有匹配“${lobby.query.trim()}”的房间',
            action: PillButton(
              label: '清除筛选',
              style: PillButtonStyle.secondary,
              onPressed: _clearFilter,
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          AlistenSpacing.page,
          0,
          AlistenSpacing.page,
          bottom,
        ),
        sliver: SliverList.separated(
          itemCount: rooms.length,
          separatorBuilder: (_, _) => const SizedBox(height: AlistenSpacing.sm),
          itemBuilder: (context, index) {
            final room = rooms[index];
            return _RoomCard(
              room: room,
              joining: _joining == room.id,
              onPressed: lobby.busy || _joinSheetShown
                  ? null
                  : () => unawaited(_join(room)),
            );
          },
        ),
      ),
    ];
  }
}

// 吸顶头部的高度须预先算出并随系统字号变化：操作栏按胶囊按钮的高度算（栏内
// 小标题与它同字号），大标题区按字号算。
final class _LobbyHeader extends SliverPersistentHeaderDelegate {
  _LobbyHeader({
    required this.topInset,
    required TextScaler scaler,
    required double barExtent,
    required this.actions,
  }) : barExtent = (barExtent + 2 * AlistenSpacing.xxs).ceilToDouble(),
       titleExtent = _titleExtent(scaler);

  final double topInset;
  final double barExtent;
  final double titleExtent;
  final List<Widget> actions;

  // 出自游戏 Metaphor: ReFantazio（《暗喻幻想：ReFantazio》）。
  static const _tagline = '音乐是最先诞生在这世界上的魔法';

  static double _titleExtent(TextScaler scaler) {
    double line(TextStyle style) =>
        scaler.scale(style.fontSize!) * style.height!;
    return (line(AlistenTypography.largeTitle) +
                AlistenSpacing.xxs +
                line(AlistenTypography.secondary))
            .ceilToDouble() +
        AlistenSpacing.sm;
  }

  @override
  double get minExtent => topInset + barExtent;

  @override
  double get maxExtent => minExtent + titleExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = AlistenColors.of(context);
    final collapsed = (shrinkOffset / titleExtent).clamp(0.0, 1.0);
    // 大标题基本移出后小标题才淡入，避免两者同时可见。
    final small = ((collapsed - 0.6) / 0.4).clamp(0.0, 1.0);
    final barTitle = AlistenTypography.weighted(
      AlistenTypography.bodyStrong,
      FontWeight.w700,
    ).copyWith(color: colors.onGlass);
    return ToastClearance(
      child: SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.floor.withValues(alpha: colors.floor.a * collapsed),
            border: Border(
              bottom: BorderSide(
                color: colors.glassStroke.withValues(
                  alpha: colors.glassStroke.a * collapsed,
                ),
              ),
            ),
          ),
          child: Column(
            children: [
              SizedBox(height: topInset),
              SizedBox(
                height: barExtent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AlistenSpacing.xs,
                    vertical: AlistenSpacing.xxs,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: AlistenSpacing.sm),
                      Expanded(
                        child: small == 0
                            ? const SizedBox.shrink()
                            : ExcludeSemantics(
                                child: Opacity(
                                  opacity: small,
                                  child: Text(
                                    'Alisten',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: barTitle,
                                  ),
                                ),
                              ),
                      ),
                      for (final (index, action) in actions.indexed) ...[
                        if (index > 0)
                          const SizedBox(width: AlistenSpacing.xxs),
                        action,
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: AlignmentDirectional.bottomStart,
                    minHeight: titleExtent,
                    maxHeight: titleExtent,
                    child: Opacity(
                      opacity: 1 - collapsed,
                      alwaysIncludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AlistenSpacing.page,
                          0,
                          AlistenSpacing.page,
                          AlistenSpacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback:
                                    colors.brandGradient.createShader,
                                child: Text(
                                  'Alisten',
                                  maxLines: 1,
                                  style: AlistenTypography.largeTitle.copyWith(
                                    color: colors.onGlass,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AlistenSpacing.xxs),
                            Text(
                              _tagline,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AlistenTypography.secondary.copyWith(
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
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_LobbyHeader oldDelegate) => true;
}

typedef _Continue = ({
  String id,
  String? name,
  NowPlaying? nowPlaying,
  RoomConnectionStatus status,
});

_Continue? _continueOf(RoomState room) {
  final id = room.activeRoomId;
  // 已停止或被拒绝的房间不能继续收听，由迷你播放条说明原因。
  if (id == null || room.failure != null) return null;
  return (
    id: id,
    name: room.snapshot?.room.name ?? room.roomName,
    nowPlaying: room.snapshot?.nowPlaying,
    status: room.status,
  );
}

class _ContinueListening extends ConsumerWidget {
  const _ContinueListening({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(roomControllerProvider.select(_continueOf));
    if (room == null) return const SliverToBoxAdapter();
    final colors = AlistenColors.of(context);
    final meta = room.nowPlaying?.entry.meta;
    final (subtitle, ink) = switch (meta) {
      final meta? => (
        [meta.title, meta.artist].where((part) => part.isNotEmpty).join(' · '),
        colors.onGlassMuted,
      ),
      null when room.status != RoomConnectionStatus.open => (
        '正在连接房间…',
        colors.warning,
      ),
      null => ('房间暂时没有播放', colors.onGlassMuted),
    };
    final shape = BorderRadius.circular(AlistenRadii.lg);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AlistenSpacing.page,
        AlistenSpacing.xs,
        AlistenSpacing.page,
        0,
      ),
      sliver: SliverToBoxAdapter(
        child: Pressable(
          onPressed: () => onOpen(room.id),
          focusRadius: shape,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: shape,
              border: Border.all(color: colors.glassStroke),
            ),
            child: ClipRRect(
              borderRadius: shape,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CoverBackdrop(
                      url: meta?.coverUrl,
                      child: ColoredBox(color: colors.glassFill),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AlistenSpacing.md),
                    child: Row(
                      children: [
                        // 不带 Hero 标签：迷你播放条已使用
                        // `cover-<entryId>`，同一路由子树内标签必须唯一。
                        CoverArt(
                          url: meta?.coverUrl,
                          size: AlistenSizes.featureCover,
                          radius: AlistenRadii.md,
                        ),
                        const SizedBox(width: AlistenSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.graphic_eq_rounded,
                                    size: AlistenSizes.inlineIcon,
                                    color: colors.glow,
                                  ),
                                  const SizedBox(width: AlistenSpacing.xxs),
                                  Flexible(
                                    child: Text(
                                      '继续收听',
                                      style: AlistenTypography.caption.copyWith(
                                        color: colors.onGlassMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AlistenSpacing.xxs),
                              Text(
                                room.name ?? '房间',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AlistenTypography.weighted(
                                  AlistenTypography.title,
                                  FontWeight.w700,
                                ).copyWith(color: colors.onGlass),
                              ),
                              const SizedBox(height: AlistenSpacing.xxs / 2),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AlistenTypography.secondary.copyWith(
                                  color: ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AlistenSpacing.xs),
                        ExcludeSemantics(
                          child: Container(
                            width: AlistenSizes.iconButton,
                            height: AlistenSizes.iconButton,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: colors.brandGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: colors.glow.withValues(
                                    alpha: AlistenTint.glow,
                                  ),
                                  blurRadius: AlistenSpacing.lg,
                                  offset: const Offset(0, AlistenSpacing.xxs),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: AlistenSizes.icon,
                              color: colors.onBrand,
                            ),
                          ),
                        ),
                      ],
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

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.joining,
    required this.onPressed,
  });

  final RoomListing room;
  final bool joining;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final identity = AlistenColors.identity(room.id);
    final name = room.name.trim();
    final online = room.onlineCount > 0;
    return Pressable(
      onPressed: onPressed,
      // 进房期间卡片不可点但不变淡，由正在进入的卡片显示转圈。
      dimWhenDisabled: false,
      focusRadius: BorderRadius.circular(AlistenRadii.md),
      child: GlassPanel(
        padding: const EdgeInsets.all(AlistenSpacing.sm),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: AlistenSizes.rowCover,
                height: AlistenSizes.rowCover,
                decoration: BoxDecoration(
                  gradient: identity.fill,
                  borderRadius: BorderRadius.circular(AlistenRadii.sm),
                ),
                alignment: Alignment.center,
                child: Text(
                  name.isEmpty ? '#' : name.characters.first.toUpperCase(),
                  // 首字跟随色块尺寸，不随系统字号缩放，否则会撑破色块。
                  textScaler: TextScaler.noScaling,
                  style: AlistenTypography.weighted(
                    AlistenTypography.title,
                    FontWeight.w800,
                  ).copyWith(color: identity.ink),
                ),
              ),
            ),
            const SizedBox(width: AlistenSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AlistenTypography.bodyStrong.copyWith(
                      color: colors.onGlass,
                    ),
                  ),
                  if (room.description.isNotEmpty)
                    Text(
                      room.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AlistenTypography.secondary.copyWith(
                        color: colors.onGlassMuted,
                      ),
                    ),
                  const SizedBox(height: AlistenSpacing.xs),
                  Wrap(
                    spacing: AlistenSpacing.sm,
                    runSpacing: AlistenSpacing.xxs,
                    children: [
                      _Badge(
                        ink: online ? colors.success : colors.onGlassMuted,
                        label: '${room.onlineCount} 人在线',
                        leading: Container(
                          width: AlistenSpacing.xs,
                          height: AlistenSpacing.xs,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: online ? colors.success : null,
                            border: Border.all(
                              color: online
                                  ? colors.success
                                  : colors.onGlassMuted,
                            ),
                          ),
                        ),
                      ),
                      if (room.hasPassword)
                        _Badge(
                          ink: colors.onGlassMuted,
                          label: '需要密码',
                          leading: Icon(
                            Icons.lock_rounded,
                            size: AlistenSizes.inlineIcon,
                            color: colors.onGlassMuted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AlistenSpacing.xs),
            SizedBox.square(
              dimension: AlistenSizes.icon,
              child: Center(
                child: joining
                    ? const BusyIndicator(
                        size: AlistenSizes.iconSm,
                        semanticLabel: '正在进入',
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        size: AlistenSizes.icon,
                        color: colors.onGlassMuted,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.leading, required this.ink, required this.label});

  final Widget leading;
  final Color ink;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        const SizedBox(width: AlistenSpacing.xxs),
        Flexible(
          child: Text(
            label,
            style: AlistenTypography.weighted(
              AlistenTypography.secondary,
              FontWeight.w600,
            ).copyWith(color: ink),
          ),
        ),
      ],
    );
  }
}
