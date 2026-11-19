import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:alisten/domain/member/member.dart';
import 'package:alisten/features/chat/presentation/member_list.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/motion.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/edge_fade.dart';
import 'package:alisten/shared/ui/glyph_cascade.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _stripAvatars = 5;

const _stripStep = AlistenSizes.avatar - AlistenSpacing.sm;

// 成员面板最多占屏幕的这一份高度，至少能放下标题和两三个成员。
const _panelShare = 0.6;
const _panelMinHeight = 160.0;

// 列表最多露出这么多行，再多在面板里滑动查看；正好是成员条上头像的个数，飞
// 过来的头像都落在看得见的行里。
const _visibleMembers = _stripAvatars;

// 上面或下面还有成员时，那一侧在这么高的带里渐隐。
const _listFade = AlistenSpacing.xl;

// 向上推成员面板超过这么远，或甩出这么快（像素每秒），就收起。
const _pushToClose = 24.0;
const _flickToClose = 300.0;

// 展开的时间线，单位毫秒。卡片向下展开用 374 毫秒减速停稳，不冲过头。头像依次
// 出发，每个晚 34 毫秒，像被拿起来放进各自那一行；人数和“成员”晚 34 毫秒出发，
// 等头像先离开这一行再滑过去。头像快落位时昵称逐字弹出，上面的行先开始。
const _unfold = Duration(milliseconds: 1100);
const _moveMs = 374.0;
const _avatarsStaggerMs = 34.0;
const _headDelayMs = 34.0;
const _namesFromMs = 272.0;
const _namesStaggerMs = 34.0;
const _namesStaggerRows = 6;

// 没有头像飞过来的行，头像随昵称在这段时间里淡入。
const _rowAvatarFadeMs = 200.0;

// 头像飞到半路时放大这么多、投下影子，落位时放回原大。
const _lift = 0.1;

// 收起：昵称先淡出，随后头像飞回成员条、卡片收回。
const _fold = Duration(milliseconds: 360);
const _foldNames = Interval(0, 0.35);
const _foldMove = Interval(0.15, 1, curve: Curves.easeInOutCubic);

// 卡片在展开的这段进度里铺满底色，收起时在同一段里淡去。
const _fillBy = 0.25;

// 成员条上的“+n”在列表里没有对应的东西，在这段进度里淡去。
const _moreGoneBy = 0.4;

String _onlineText(int online, int? capacity) {
  return capacity == null ? '$online 人在线' : '$online / $capacity 人在线';
}

// 在线人数取服务端按会话（每台设备一个）计的值，与房间顶栏和大厅一致。
/// 成员条点开，面板盖住成员条向下展开：前几个头像落到各自那一行，在线人数滑到
/// 标题处，随后昵称从左往右显出。点标题、往上推、点空白处或返回就收回成员条。
class MemberStrip extends ConsumerStatefulWidget {
  const MemberStrip({super.key});

  @override
  ConsumerState<MemberStrip> createState() => _MemberStripState();
}

class _MemberStripState extends ConsumerState<MemberStrip>
    with TickerProviderStateMixin {
  // 页面构建期间不能显示 overlay 子组件，所以在组件存活期间始终显示；面板只在
  // 展开或收起途中构建。
  final _portal = OverlayPortalController()..show();
  final _link = LayerLink();

  late final _unfolding = AnimationController(vsync: this, duration: _unfold)
    ..addStatusListener(_onSettled);
  late final _folding = AnimationController(vsync: this, duration: _fold)
    ..addStatusListener(_onSettled);
  bool _open = false;

  // 这次动画开始时的位置进度：还没展开完就收起、还没收完又展开时从这里接着走。
  double _from = 0;

  // 开始收起时昵称显出到哪了。
  double _namesAtFold = 1;
  double _panelHeight = 0;
  double _pushed = 0;

  // 成员列表上面、下面是否还有没露出来的成员。
  bool _moreAbove = false;
  bool _moreBelow = false;
  final _precached = <String>{};

  // 成员条和面板里对应的部件，飞行的起点和终点按它们实际排好的位置算。
  final _strip = GlobalKey();
  final _stack = GlobalKey();
  final _count = GlobalKey();
  final _trail = GlobalKey();
  final _panel = GlobalKey();
  final _headCount = GlobalKey();
  final _headTrail = GlobalKey();
  final _viewport = GlobalKey();
  final _rowAvatars = [
    for (var index = 0; index < _stripAvatars; index++) GlobalKey(),
  ];

  bool get _shown => _open || _folding.isAnimating;

  // 展开时出发晚 [delayMs] 毫秒的部分移动到哪了。
  double _moved(double delayMs) {
    final ms = _unfolding.value * _unfold.inMilliseconds - delayMs;
    final moved = Curves.easeOutCubic.transform((ms / _moveMs).clamp(0.0, 1.0));
    return lerpDouble(_from, 1, moved)!;
  }

  // 标题行里的人数和“成员”移动到哪了。
  double get _headProgress => _open ? _moved(_headDelayMs) : _progress;

  // 第 [index] 个头像飞到哪了。收起时一起飞回。
  double _avatarProgress(int index) =>
      _open ? _moved(_avatarsStaggerMs * index) : _progress;

  bool get _settled => _open && !_unfolding.isAnimating;

  double get _progress {
    if (_open) return _moved(0);
    if (_folding.isAnimating) {
      return _from * (1 - _foldMove.transform(_folding.value));
    }
    return 0;
  }

  void _onSettled(AnimationStatus status) {
    if (status.isCompleted && mounted) setState(() {});
  }

  @override
  void dispose() {
    _unfolding.dispose();
    _folding.dispose();
    super.dispose();
  }

  void _toggle() => _open ? _close() : _unfoldPanel();

  void _unfoldPanel() {
    final media = MediaQuery.of(context);
    final box = _strip.currentContext?.findRenderObject();
    final top = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero).dy
        : 0.0;
    // 不盖过键盘，也不超过屏幕的六成。
    _panelHeight = math.min(
      media.size.height * _panelShare,
      media.size.height -
          media.viewInsets.bottom -
          media.padding.bottom -
          top -
          AlistenSpacing.xl,
    );
    _from = _progress;
    _folding
      ..stop()
      ..value = 0;
    setState(() => _open = true);
    if (reducedMotion(context)) {
      _unfolding.value = 1;
    } else {
      unawaited(_unfolding.forward(from: 0));
    }
  }

  void _close() {
    if (!_open) return;
    _from = _progress;
    _namesAtFold = _unfolding.value;
    _unfolding.stop();
    setState(() => _open = false);
    if (!reducedMotion(context)) unawaited(_folding.forward(from: 0));
  }

  // 列表滚到哪、内容有多长决定两端要不要渐隐；尺寸通知在布局后才到，首次
  // 展开也会上报。
  bool _onListScroll(Notification notification) {
    final metrics = switch (notification) {
      ScrollNotification(:final metrics, depth: 0) => metrics,
      ScrollMetricsNotification(:final metrics, depth: 0) => metrics,
      _ => null,
    };
    if (metrics == null) return false;
    final above = metrics.extentBefore > 0.5;
    final below = metrics.extentAfter > 0.5;
    if (above != _moreAbove || below != _moreBelow) {
      setState(() {
        _moreAbove = above;
        _moreBelow = below;
      });
    }
    return false;
  }

  // 向上推过一点或向上甩就收起，方向与它展开的方向相反。
  void _onPushEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_pushed < -_pushToClose || velocity < -_flickToClose) _close();
    _pushed = 0;
  }

  // 第 [row] 行头像右边的内容：开始逐字弹出后过了几秒，以及整体的不透明度。
  ({double elapsed, double opacity}) _names(int row) {
    final fromMs =
        _namesFromMs + _namesStaggerMs * math.min(row, _namesStaggerRows);
    double elapsed(double clock) =>
        (clock * _unfold.inMilliseconds - fromMs) / 1000;
    if (_open) return (elapsed: elapsed(_unfolding.value), opacity: 1);
    return (
      elapsed: elapsed(_namesAtFold),
      opacity: 1 - _foldNames.transform(_folding.value),
    );
  }

  // 下次展开时头像要飞到各行的大小，先解码好，飞的时候第一帧就有图。
  void _precache(List<Member> members) {
    for (final member in members) {
      final url = member.avatarUrl(AlistenSizes.listAvatar);
      if (url != null && _precached.add(url)) {
        unawaited(precacheMemberAvatar(context, url, AlistenSizes.listAvatar));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final sessions =
        ref.watch(
          roomControllerProvider.select((room) => room.snapshot?.members),
        ) ??
        const <Member>[];
    final online = ref.watch(
      roomControllerProvider.select((room) => room.snapshot?.onlineCount ?? 0),
    );
    final capacity = ref.watch(
      roomControllerProvider.select((room) => room.snapshot?.room.capacity),
    );
    final self = ref.watch(
      roomControllerProvider.select((room) => room.member?.id),
    );
    final members = [
      for (final (:member, sessions: _) in membersOf(sessions)) member,
    ];
    final shown = members.take(_stripAvatars).toList(growable: false);
    final more = members.length - shown.length;
    final count = _onlineText(online, capacity);
    _precache(shown);
    final strip = Pressable(
      semanticLabel: '查看房间成员',
      expanded: _open,
      ink: false,
      onPressed: _toggle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AlistenSizes.minTouchTarget,
        ),
        child: Padding(
          // 与下方时间线中的头像对齐。
          padding: const EdgeInsets.fromLTRB(
            AlistenSpacing.sm,
            AlistenSpacing.xxs,
            AlistenSpacing.xs,
            AlistenSpacing.xxs,
          ),
          // 面板展开期间由面板画出头像和人数，成员条上的藏起来。
          child: Opacity(
            opacity: _shown ? 0 : 1,
            child: Row(
              children: [
                if (shown.isNotEmpty) ...[
                  _AvatarStack(key: _stack, members: shown, more: more),
                  const SizedBox(width: AlistenSpacing.sm),
                ],
                Expanded(child: _Count(count, key: _count)),
                ExcludeSemantics(child: _Trail(turns: 0, key: _trail)),
              ],
            ),
          ),
        ),
      ),
    );
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _open) _close();
      },
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => _shown
              ? _overlay(
                  colors,
                  sessions: sessions,
                  self: self,
                  shown: shown,
                  more: more,
                  count: count,
                )
              : const SizedBox.shrink(),
          child: ExcludeSemantics(
            excluding: _shown,
            child: KeyedSubtree(key: _strip, child: strip),
          ),
        ),
      ),
    );
  }

  Widget _overlay(
    AlistenColors colors, {
    required List<Member> sessions,
    required String? self,
    required List<Member> shown,
    required int more,
    required String count,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 接住关闭面板的点按，不传给页面。与模态遮罩不同，读屏仍能访问页面，
        // 并多一个关闭入口。
        if (_open)
          Semantics(
            container: true,
            button: true,
            label: '关闭',
            onTap: _close,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: _close,
            ),
          ),
        Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            child: IgnorePointer(
              ignoring: !_open,
              child: AnimatedBuilder(
                animation: Listenable.merge([_unfolding, _folding]),
                builder: (context, _) => _unfolded(
                  colors,
                  sessions: sessions,
                  self: self,
                  shown: shown,
                  more: more,
                  count: count,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _unfolded(
    AlistenColors colors, {
    required List<Member> sessions,
    required String? self,
    required List<Member> shown,
    required int more,
    required String count,
  }) {
    final strip = _box(_strip);
    if (strip == null) return const SizedBox.shrink();
    final progress = _progress;
    final settled = _settled;
    final panel = _box(_panel);
    final viewport = panel == null ? null : _rectIn(_viewport, panel);
    // 头像落点在列表看得见的范围里才飞过去，否则在成员条上原地淡出、淡入。
    Rect? landing(GlobalKey key) {
      if (panel == null || viewport == null) return null;
      final rect = _rectIn(key, panel);
      final visible = viewport.inflate(0.5);
      return rect != null &&
              visible.contains(rect.topLeft) &&
              visible.contains(rect.bottomRight)
          ? rect
          : null;
    }

    final landings = [
      for (final key in _rowAvatars.take(shown.length)) landing(key),
    ];
    bool flying(int row) => row < landings.length && landings[row] != null;
    // 落了地的头像交给列表那一行，停稳的人数交给标题行。
    bool landed(int row) => _open && flying(row) && _avatarProgress(row) >= 1;
    final headLanded = _open && _headProgress >= 1;
    final fill = (progress / _fillBy).clamp(0.0, 1.0);
    final shadow = Theme.of(context).colorScheme.shadow.withValues(alpha: 0.24);
    final card = DecoratedBox(
      key: const ValueKey('member-panel'),
      decoration: BoxDecoration(
        color: colors.raised.withValues(alpha: colors.raised.a * fill),
        borderRadius: BorderRadius.circular(AlistenRadii.md),
        border: Border.all(
          color: colors.glassStroke.withValues(
            alpha: colors.glassStroke.a * fill,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: shadow.withValues(alpha: shadow.a * progress),
            blurRadius: AlistenSpacing.xl,
            offset: const Offset(0, AlistenSpacing.xs),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AlistenRadii.md),
        child: _Unfold(
          progress: progress,
          from: strip.size.height,
          child: _content(
            colors,
            sessions: sessions,
            self: self,
            settled: settled,
            count: count,
            flying: flying,
            landed: landed,
            headLanded: headLanded,
          ),
        ),
      ),
    );
    return SizedBox(
      key: _panel,
      width: strip.size.width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.xs),
            child: card,
          ),
          if (!settled)
            ..._flights(
              landed: landed,
              headLanded: headLanded,
              strip: strip,
              panel: panel,
              progress: progress,
              shown: shown,
              more: more,
              count: count,
              landings: landings,
            ),
        ],
      ),
    );
  }

  Widget _content(
    AlistenColors colors, {
    required List<Member> sessions,
    required String? self,
    required bool settled,
    required String count,
    required bool Function(int row) flying,
    required bool Function(int row) landed,
    required bool headLanded,
  }) {
    final grabber = Semantics(
      container: true,
      button: true,
      label: '收起成员',
      onTap: _close,
      child: SizedBox(
        height: AlistenSizes.minTouchTarget * 0.6,
        width: double.infinity,
        child: Center(
          child: Container(
            width: AlistenSizes.sheetHandle.width,
            height: AlistenSizes.sheetHandle.height,
            decoration: BoxDecoration(
              color: colors.onGlass.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AlistenRadii.pill),
            ),
          ),
        ),
      ),
    );
    // 标题行与成员条同高、同在一处：人数和“成员”在这一行里左右移动。动画途中
    // 由飞行层画出它们，这里只占位。
    final header = Pressable(
      semanticLabel: '查看房间成员',
      expanded: _open,
      ink: false,
      onPressed: _close,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AlistenSizes.minTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlistenSpacing.sm,
            vertical: AlistenSpacing.xxs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Opacity(
                  opacity: headLanded ? 1 : 0,
                  alwaysIncludeSemantics: true,
                  child: _Count(count, key: _headCount),
                ),
              ),
              ExcludeSemantics(
                child: Opacity(
                  opacity: headLanded ? 1 : 0,
                  child: _Trail(turns: 0.5, key: _headTrail),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // 读屏用“收起成员”按钮收起；手势不能把标题和按钮并成一个节点。
      excludeFromSemantics: true,
      onVerticalDragUpdate: (details) => _pushed += details.delta.dy,
      onVerticalDragEnd: _onPushEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.max(_panelHeight, _panelMinHeight),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _visibleMembers * MemberList.rowExtent(context),
                ),
                child: NotificationListener<Notification>(
                  onNotification: _onListScroll,
                  child: EdgeFade(
                    top: _moreAbove ? _listFade : 0,
                    bottom: _moreBelow ? _listFade : 0,
                    child: SingleChildScrollView(
                      key: _viewport,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AlistenSpacing.sm,
                      ),
                      child: MemberList(
                        sessions: sessions,
                        selfId: self,
                        // 飞过来的头像落地前，行里的头像先不画，落地就交给这一行，
                        // 滚动时跟着走；其余行的头像随昵称一起淡入。
                        avatar: (row, avatar) {
                          final names = _names(row);
                          return Opacity(
                            opacity: settled || landed(row)
                                ? 1
                                : flying(row)
                                ? 0
                                : (names.elapsed * 1000 / _rowAvatarFadeMs)
                                          .clamp(0.0, 1.0) *
                                      names.opacity,
                            child: row < _rowAvatars.length
                                ? KeyedSubtree(
                                    key: _rowAvatars[row],
                                    child: avatar,
                                  )
                                : avatar,
                          );
                        },
                        details: (row, details) {
                          final names = settled
                              ? (elapsed: glyphCascadeSeconds, opacity: 1.0)
                              : _names(row);
                          return Opacity(
                            opacity: names.elapsed > 0 ? names.opacity : 0,
                            alwaysIncludeSemantics: true,
                            child: GlyphCascade(
                              elapsed: names.elapsed,
                              child: details,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            grabber,
          ],
        ),
      ),
    );
  }

  List<Widget> _flights({
    required bool Function(int row) landed,
    required bool headLanded,
    required RenderBox strip,
    required RenderBox? panel,
    required double progress,
    required List<Member> shown,
    required int more,
    required String count,
    required List<Rect?> landings,
  }) {
    final stack = _rectIn(_stack, strip);
    final countFrom = _rectIn(_count, strip);
    final trailFrom = _rectIn(_trail, strip);
    Rect? inPanel(GlobalKey key) => panel == null ? null : _rectIn(key, panel);
    final head = _headProgress;
    // 面板还没排好时（展开的第一帧）落点就是起点。
    Rect toward(Rect from, Rect? to) => Rect.lerp(from, to ?? from, head)!;
    final surface = Theme.of(context).colorScheme.surface;
    return [
      // 头像飞在人数上面：它们像被拿起来，从文字上方经过。
      if (countFrom != null && !headLanded)
        Positioned.fromRect(
          rect: toward(countFrom, inPanel(_headCount)),
          child: IgnorePointer(child: ExcludeSemantics(child: _Count(count))),
        ),
      if (trailFrom != null && !headLanded)
        Positioned.fromRect(
          rect: toward(trailFrom, inPanel(_headTrail)),
          child: IgnorePointer(
            child: ExcludeSemantics(child: _Trail(turns: 0.5 * head)),
          ),
        ),
      if (stack != null && more > 0)
        Positioned(
          left: stack.left + _stripStep * shown.length,
          top: stack.top,
          child: IgnorePointer(
            child: Opacity(
              opacity: (1 - progress / _moreGoneBy).clamp(0.0, 1.0),
              child: _More(more),
            ),
          ),
        ),
      if (stack != null)
        for (final (index, member) in shown.indexed)
          if (!landed(index))
            _avatarFlight(
              member,
              from: Rect.fromLTWH(
                stack.left + _stripStep * index,
                stack.top,
                AlistenSizes.avatar,
                AlistenSizes.avatar,
              ),
              to: landings[index],
              progress: _avatarProgress(index),
              ring: surface,
              shadow: Theme.of(context).colorScheme.shadow,
            ),
    ];
  }

  // 头像按列表里的大小画、整体缩放，飞行途中图片不必按每一帧的大小重新解码。
  Widget _avatarFlight(
    Member member, {
    required Rect from,
    required Rect? to,
    required double progress,
    required Color ring,
    required Color shadow,
  }) {
    final rect = to == null ? from : Rect.lerp(from, to, progress)!;
    final scale = rect.width / AlistenSizes.listAvatar;
    final lifted = to == null ? 0.0 : math.sin(math.pi * progress);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: AlistenSizes.listAvatar,
      height: AlistenSizes.listAvatar,
      child: IgnorePointer(
        child: Opacity(
          opacity: to == null ? 1 - progress : 1,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: Transform.scale(
              scale: 1 + _lift * lifted,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: shadow.withValues(alpha: 0.24 * lifted),
                      blurRadius: AlistenSpacing.xs,
                      offset: const Offset(0, AlistenSpacing.xxs),
                    ),
                  ],
                ),
                // 成员条上叠放的头像靠白边分开，落到各行时白边淡去。
                foregroundDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ring.withValues(alpha: ring.a * (1 - progress)),
                    width: AlistenSizes.ring / scale,
                  ),
                ),
                child: MemberAvatar(
                  key: ValueKey('member-flight-${member.id}'),
                  name: member.name,
                  imageUrl: member.avatarUrl(AlistenSizes.listAvatar),
                  size: AlistenSizes.listAvatar,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  RenderBox? _box(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  Rect? _rectIn(GlobalKey key, RenderBox ancestor) {
    final box = _box(key);
    if (box == null || !ancestor.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: ancestor) & box.size;
  }
}

class _Count extends StatelessWidget {
  const _Count(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AlistenTypography.weighted(
        AlistenTypography.secondary,
        FontWeight.w700,
      ).copyWith(color: AlistenColors.of(context).onGlass),
    );
  }
}

class _Trail extends StatelessWidget {
  const _Trail({required this.turns, super.key});

  final double turns;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '成员',
          style: AlistenTypography.secondary.copyWith(
            color: colors.onGlassMuted,
          ),
        ),
        Transform.rotate(
          angle: turns * 2 * math.pi,
          child: Icon(
            AlistenIcons.caretDown,
            size: AlistenSizes.iconSm,
            color: colors.onGlassMuted,
          ),
        ),
      ],
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.members, required this.more, super.key});

  final List<Member> members;
  final int more;

  @override
  Widget build(BuildContext context) {
    final count = members.length + (more > 0 ? 1 : 0);
    return SizedBox(
      width: _stripStep * (count - 1) + AlistenSizes.avatar,
      height: AlistenSizes.avatar,
      child: Stack(
        children: [
          for (var index = 0; index < members.length; index++)
            Positioned(
              left: _stripStep * index,
              child: MemberAvatar(
                name: members[index].name,
                imageUrl: members[index].avatarUrl(AlistenSizes.avatar),
                ring: true,
              ),
            ),
          if (more > 0)
            Positioned(left: _stripStep * members.length, child: _More(more)),
        ],
      ),
    );
  }
}

class _More extends StatelessWidget {
  const _More(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Container(
      width: AlistenSizes.avatar,
      height: AlistenSizes.avatar,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.raised,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: AlistenSizes.ring,
        ),
      ),
      child: Text(
        '+$count',
        // 数字按圆形大小排版，不随字体缩放；旁边的在线人数已完整给出人数。
        textScaler: TextScaler.noScaling,
        style: AlistenTypography.caption.copyWith(color: colors.onGlass),
      ),
    );
  }
}

/// 按 [progress] 露出 [child] 的上面一截：从 [from] 高到 [child] 的全高。
/// [child] 始终按全高排版，露出多少由外面的裁剪决定，各行不会随着展开挪动。
class _Unfold extends SingleChildRenderObjectWidget {
  const _Unfold({
    required this.progress,
    required this.from,
    required super.child,
  });

  final double progress;
  final double from;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderUnfold(progress, from);

  @override
  void updateRenderObject(BuildContext context, _RenderUnfold renderObject) {
    renderObject
      ..progress = progress
      ..from = from;
  }
}

class _RenderUnfold extends RenderProxyBox {
  _RenderUnfold(this._progress, this._from);

  double _progress;
  set progress(double value) {
    if (value == _progress) return;
    _progress = value;
    markNeedsLayout();
  }

  double _from;
  set from(double value) {
    if (value == _from) return;
    _from = value;
    markNeedsLayout();
  }

  Size _sizeFor(Size full, BoxConstraints constraints) {
    final from = math.min(_from, full.height);
    return constraints.constrain(
      Size(full.width, lerpDouble(from, full.height, _progress)!),
    );
  }

  @override
  void performLayout() {
    final child = this.child!..layout(constraints, parentUsesSize: true);
    size = _sizeFor(child.size, constraints);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _sizeFor(child!.getDryLayout(constraints), constraints);
}
