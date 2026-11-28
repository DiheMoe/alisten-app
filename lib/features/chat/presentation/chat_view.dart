import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/chat/application/chat_controller.dart';
import 'package:alisten/features/chat/application/chat_item.dart';
import 'package:alisten/features/chat/presentation/member_panel.dart';
import 'package:alisten/features/chat/presentation/send_flight.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/motion.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/animated_resize.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/edge_fade.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:alisten/shared/ui/outer_horizontal_drag.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderDecoratedBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _bottomDistance = 60.0;

// 同一发送者间隔不超过此时长的消息共用一个头像。
const _runWindowMs = 2 * 60 * 1000;

// 消息间隔超过此时长时，下一条消息上方显示时间。
const _pauseMs = 5 * 60 * 1000;

// 自己的头像在飞行气泡到达落点后这么快淡入。
const _avatarIn = Duration(milliseconds: 120);

// 别人新发来的行：前 0.27 秒从零长到原高，把上面的行推上去；内容在前 0.18 秒
// 淡入；气泡从靠头像的一角由 0.8 倍放大，落定时和自己发出的消息一样轻轻一弹。
const _entrance = Duration(milliseconds: 450);
const _entranceGrow = Interval(0, 0.6, curve: Curves.easeOutCubic);
const _entranceFade = Interval(0, 0.4, curve: Curves.easeOut);
const _entranceScale = 0.8;

// 列表会把高度为零、贴在边上的行当作已经滚出视野回收掉，从这么一点点高起步。
const _entranceLeast = 0.001;

// 一次涌进来比这更多行时直接显示（如断线重连后补齐），不一条条地弹。
const _entranceMost = 3;

// 输入框飞出去之后，新的空输入框晚 0.12 秒从 94% 大小展开并淡入，共 0.37 秒。
const _fieldReturn = Duration(milliseconds: 370);
const _fieldReturnMove = Interval(0.32, 1, curve: Curves.easeOutCubic);
const _fieldReturnScale = 0.94;

// 草稿超过此字数后，输入框显示剩余可输入字数。
const _lengthHintFrom = 450;

const _bubblePadding = EdgeInsets.symmetric(
  horizontal: AlistenSpacing.sm,
  vertical: AlistenSpacing.xs,
);

// 气泡不横跨整个时间线，从位置就能看出是谁的消息。
const _farGutter = AlistenSpacing.xxxl;

// 时间线固定点及其之前各行所在的 sliver。
const _aboveKey = ValueKey('chat-above-anchor');

class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key});

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _scroll = ScrollController();

  /// 正在从输入框飞进时间线的消息：行键对应落点气泡的键。房间广播回来时
  /// 换成新的行键，落点不变。
  final _flying = <String, GlobalKey>{};

  // 飞行中的气泡已经到过落点的那几条消息，按落点的键记。
  final _arrived = <GlobalKey>{};

  // 刚收到、要做入场动画的行，按行的键记；动画结束后移除。
  final _entering = <String>{};

  // 上一帧以来别人新发来的行。一批里的消息是一条条到的，到下一次构建时才知道
  // 这一批有多少。
  final _arrivals = <String>[];
  final _flights = <OverlayEntry>{};

  /// 时间线所在的区域，飞行只画在它和输入框里，不盖住成员条和房间顶栏。
  final _timelineArea = GlobalKey();

  /// 布局在固定点之上的最新一行。读者离开底部期间新到的行布局在固定点之下，
  /// 正在读的内容才保持不动；为 null 时所有行都在固定点之上。
  String? _anchor;

  /// 在底部时显示最新的 `visibleCount` 行；离开底部后顶部不再移除行，正在读的
  /// 行和 [_anchor] 都保持不变。
  String? _oldestShown;

  /// 测量之前，控制器的 `atBottom` 是上一个视图留下的值。
  bool _measured = false;

  /// 时间线自行滚向最新一行期间不算读者离开底部。
  bool _following = false;
  int _followRun = 0;

  /// 自行跳转途经的位置按跳转前的各行测得，不能采用。
  bool _jumping = false;

  /// 最新一行是否在视野内的测量结果，尚未告知控制器。
  bool? _unreported;

  /// 滚向最新一行的动画越过终点后为 true，等待停下。
  bool _arrivalScheduled = false;

  /// 手指按下会停住滚动但不开始新的滚动，无法从滚动状态读出，只能自己计数。
  int _pointers = 0;

  bool get _touching => _pointers > 0;

  void _onPointerGone(PointerEvent _) {
    _pointers = math.max(0, _pointers - 1);
    // 未滚动就抬起手指时没有滚动结束通知，在此落定。
    if (!_touching) scheduleMicrotask(_settle);
  }

  @override
  void initState() {
    super.initState();
    _anchorAtLatest(ref.read(chatControllerProvider).timeline);
    _scroll.addListener(_onScrolled);
  }

  @override
  void dispose() {
    for (final flight in _flights) {
      flight.remove();
    }
    _scroll
      ..removeListener(_onScrolled)
      ..dispose();
    super.dispose();
  }

  // 开始发送：时间线回到最新一行，输入框飞向这条消息的气泡。返回是否飞了。
  bool _sent(String? key, FlightSource? source) {
    _toLatest();
    if (key == null ||
        source == null ||
        MediaQuery.disableAnimationsOf(context)) {
      return false;
    }
    final item = ref
        .read(chatControllerProvider)
        .pending
        .where((item) => item.key == key)
        .firstOrNull;
    if (item == null) return false;
    final colors = AlistenColors.of(context);
    final landing = GlobalKey();
    setState(() => _flying[key] = landing);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => SendFlight(
        text: item.text,
        source: source,
        padding: _bubblePadding,
        textStyle: AlistenTypography.body.copyWith(color: colors.onBrand),
        fill: colors.brand,
        target: () => _landingOf(landing),
        bounds: _flightBounds,
        onArrived: () {
          if (mounted) setState(() => _arrived.add(landing));
        },
        onLanded: () {
          entry.remove();
          _flights.remove(entry);
          if (!mounted) return;
          setState(() {
            _flying.removeWhere((_, key) => key == landing);
            _arrived.remove(landing);
          });
        },
      ),
    );
    _flights.add(entry);
    Overlay.of(context).insert(entry);
    return true;
  }

  // 从时间线顶部到聊天区底部（输入框）。
  Rect? _flightBounds() {
    if (!mounted) return null;
    final timeline = _timelineArea.currentContext?.findRenderObject();
    final chat = context.findRenderObject();
    if (timeline is! RenderBox ||
        chat is! RenderBox ||
        !timeline.hasSize ||
        !chat.hasSize) {
      return null;
    }
    final area = MatrixUtils.transformRect(
      chat.getTransformTo(null),
      Offset.zero & chat.size,
    );
    final top = timeline.localToGlobal(Offset.zero).dy;
    return Rect.fromLTRB(area.left, top, area.right, area.bottom);
  }

  FlightTarget? _landingOf(GlobalKey landing) {
    final box = landing.currentContext?.findRenderObject();
    if (box is! RenderDecoratedBox || !box.attached || !box.hasSize) {
      return null;
    }
    final decoration = box.decoration;
    return (
      rect: MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      ),
      radius: decoration is BoxDecoration
          ? decoration.borderRadius?.resolve(TextDirection.ltr) ??
                BorderRadius.zero
          : BorderRadius.zero,
    );
  }

  // 动画瞄准的终点部分是估算的。滚动物理允许越过实际终点时（如 iOS），动画在
  // 终点处停下而不回弹，停下要等本帧动画处理完。
  void _onScrolled() {
    if (!_following || _arrivalScheduled || !_laidOut) return;
    final position = _scroll.position;
    if (position.pixels >= position.minScrollExtent) return;
    _arrivalScheduled = true;
    scheduleMicrotask(() {
      _arrivalScheduled = false;
      if (mounted && _following && _laidOut) _arrive();
    });
  }

  void _anchorAtLatest(List<ChatItem> messages) {
    final visibleCount = ref.read(chatControllerProvider).visibleCount;
    _anchor = messages.lastOrNull?.key;
    _oldestShown = messages.isEmpty
        ? null
        : messages[math.max(0, messages.length - visibleCount)].key;
  }

  bool get _laidOut =>
      _scroll.hasClients && _scroll.position.hasContentDimensions;

  // 尺寸通知覆盖首次布局和内容尺寸变化，重建的视图（如切换模式后）因此也会
  // 上报位置。
  bool _onScrollNotification(Notification notification) {
    final metrics = switch (notification) {
      ScrollNotification(:final metrics, depth: 0) => metrics,
      ScrollMetricsNotification(:final metrics, depth: 0) => metrics,
      _ => null,
    };
    if (metrics == null || _jumping) return false;
    _report(metrics);
    // 等这条通知处理完再落定，否则在滚动结束的处理中跳转会在本次滚动内开始
    // 另一次滚动。
    if (notification is ScrollEndNotification) scheduleMicrotask(_settle);
    return false;
  }

  // 有些通知在布局期间到达（如内容尺寸变化引起的滚动开始），此时不能修改
  // provider 和 widget，所以等本帧完成后再上报。
  void _report(ScrollMetrics metrics) {
    final atBottom = metrics.extentBefore < _bottomDistance;
    if (!atBottom && _following) return;
    final scheduled = _unreported != null;
    _unreported = atBottom;
    if (!scheduled) scheduleMicrotask(_tellAtBottom);
  }

  void _tellAtBottom() {
    final atBottom = _unreported;
    _unreported = null;
    if (!mounted || atBottom == null) return;
    if (!_measured) setState(() => _measured = true);
    ref.read(chatControllerProvider.notifier).setAtBottom(atBottom);
  }

  // 读者停在底部时，把固定点之下的行移到其上而屏幕内容不动：显示窗口重新收窄，
  // 之后的新行立即显示；暂缓期间到达的行随后完整滚入视野。
  void _settle() {
    if (_following || _touching || !mounted || !_laidOut) return;
    final position = _scroll.position;
    final messages = ref.read(chatControllerProvider).timeline;
    if (_anchor == messages.lastOrNull?.key ||
        position.isScrollingNotifier.value ||
        position.extentBefore >= _bottomDistance) {
      return;
    }
    // 最新一行末端低于时间线底边的距离；固定点移到最新一行之后，时间线停在
    // 此处，屏幕内容才不变。
    final belowEdge = position.extentBefore;
    setState(() => _anchorAtLatest(messages));
    _jump(belowEdge);
    if (belowEdge > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toLatest());
    }
  }

  void _jump(double pixels) {
    _jumping = true;
    _scroll.position.jumpTo(pixels);
    _jumping = false;
  }

  // 停在底部的读者立即看到新行；离开底部或正在拖动的读者保持原位，新行放在
  // 固定点之下。
  void _onMessages(List<ChatItem>? previous, List<ChatItem> next) {
    for (final key in [..._flying.keys]) {
      if (next.any((item) => item.key == key)) continue;
      final landing = _flying.remove(key);
      final confirmed = ref
          .read(chatControllerProvider.notifier)
          .confirmedAs(key);
      if (landing != null && confirmed != null) _flying[confirmed] = landing;
    }
    final newest = next.lastOrNull?.key;
    if (newest == null || newest == previous?.lastOrNull?.key) return;
    if (!_laidOut) {
      _anchorAtLatest(next);
      return;
    }
    final position = _scroll.position;
    final held =
        !_following &&
        (position.extentBefore >= _bottomDistance ||
            position.isScrollingNotifier.value ||
            _touching);
    // 锚点行已不存在（如房间丢弃了最早的几行）时无位置可保持。
    final anchored = next.any((item) => item.key == _anchor);
    if (held && anchored) return;
    _markEntering(previous, next);
    _anchorAtLatest(next);
    _following = false;
    _followRun++;
    _jump(0);
  }

  // 停在底部时别人新发来的行做入场动画；自己发的消息由输入框飞过去。
  void _markEntering(List<ChatItem>? previous, List<ChatItem> next) {
    if (previous == null || MediaQuery.disableAnimationsOf(context)) return;
    final self = ref.read(roomControllerProvider).member?.id;
    final before = {for (final item in previous) item.key};
    final fresh = [
      for (final item in next)
        if (!before.contains(item.key) &&
            !(item is ChatMessageItem && item.member.id == self))
          item,
    ];
    _arrivals.addAll([for (final item in fresh) item.key]);
  }

  void _admitArrivals() {
    if (_arrivals.length <= _entranceMost) {
      for (final key in _arrivals) {
        _entering
          ..add(key)
          ..add('time-$key');
      }
    }
    _arrivals.clear();
  }

  // 在当前最早一行之上多显示窗口新增的行数。
  void _onVisibleCount(int? previous, int visibleCount) {
    final messages = ref.read(chatControllerProvider).timeline;
    if (messages.isEmpty) return;
    final shown = messages.indexWhere((item) => item.key == _oldestShown);
    final grown = visibleCount - (previous ?? visibleCount);
    final from = math.min(
      shown < 0 ? messages.length : shown - grown,
      messages.length - visibleCount,
    );
    _oldestShown = messages[math.max(0, from)].key;
  }

  // 先以动画滚向最新一行，再由 [_arrive] 放到真正的底部。
  void _toLatest() {
    if (!mounted || !_laidOut) return;
    final position = _scroll.position;
    final duration = AlistenDurations.of(context, AlistenDurations.medium);
    // 时长为零的动画会触发断言。
    if (duration == Duration.zero ||
        position.pixels <= position.minScrollExtent) {
      _arrive();
      return;
    }
    final run = ++_followRun;
    _following = true;
    unawaited(
      position
          .animateTo(
            position.minScrollExtent,
            duration: duration,
            curve: AlistenCurves.standard,
          )
          .whenComplete(() {
            if (run != _followRun) return;
            _following = false;
            // 滚动期间读者按下手指则由其接管，时间线在手指抬起处落定。
            if (!mounted ||
                !_laidOut ||
                _touching ||
                _scroll.position.isScrollingNotifier.value) {
              return;
            }
            _arrive();
          }),
    );
  }

  // 把所有行移到固定点之上，时间线放到起点（即最新一行的末端）。固定点之下的
  // 位置部分是估算的，所以底部以下一次布局为准。
  void _arrive() {
    final position = _scroll.position;
    final messages = ref.read(chatControllerProvider).timeline;
    if (_anchor == messages.lastOrNull?.key && position.pixels == 0) {
      _report(position);
      return;
    }
    setState(() => _anchorAtLatest(messages));
    _following = false;
    _followRun++;
    _jump(0);
    // 跳转不会上报位置，所以等布局完成后再测量。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _laidOut) _report(_scroll.position);
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(
      chatControllerProvider.select((chat) => chat.timeline),
    );
    // 只为在其变化时重建，值经由 [_oldestShown] 生效。
    ref.watch(chatControllerProvider.select((chat) => chat.visibleCount));
    final self = ref.watch(
      roomControllerProvider.select((room) => room.member?.id),
    );
    ref
      ..listen(
        chatControllerProvider.select((chat) => chat.timeline),
        _onMessages,
      )
      ..listen(
        chatControllerProvider.select((chat) => chat.visibleCount),
        _onVisibleCount,
      );
    final Widget timeline;
    if (messages.isEmpty) {
      timeline = const EmptyState(
        icon: AlistenIcons.chatsCircle,
        title: '还没有消息',
      );
    } else {
      // 只有房间丢弃了最早的几行时才找不到，那些行也已从时间线消失。
      final from = math.max(
        0,
        messages.indexWhere((item) => item.key == _oldestShown),
      );
      final rows = _rowsOf(
        messages.sublist(from),
        hasEarlier: from > 0,
        self: self,
      );
      timeline = Stack(
        children: [
          Positioned.fill(child: _timeline(rows)),
          if (_measured)
            Positioned(
              right: AlistenSpacing.sm,
              bottom: AlistenSpacing.sm,
              child: _ToLatestButton(onPressed: _toLatest),
            ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            if (constraints.maxHeight >= _stripMinHeight) const MemberStrip(),
            Expanded(
              child: GestureDetector(
                key: _timelineArea,
                behavior: HitTestBehavior.translucent,
                excludeFromSemantics: true,
                onTap: () => FocusScope.of(context).unfocus(),
                // 房间页外层有左右切换模式的分页，横拖不能被消息的文字选择吞掉。
                child: OuterHorizontalDrag(child: timeline),
              ),
            ),
            // 聊天区比输入栏还矮时（如大字号横屏手机），消息让出全部高度，输入栏
            // 贴底且可滚动，不会溢出。
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              child: SingleChildScrollView(
                reverse: true,
                primary: false,
                physics: const ClampingScrollPhysics(),
                child: _Composer(onSend: _sent),
              ),
            ),
          ],
        );
      },
    );
  }

  // [rows] 从旧到新。到 [_anchor] 为止的行从固定点向上排，其余向下排；读者
  // 离开底部后有新行到达之前，固定点就是时间线底部。
  Widget _timeline(List<_Row> rows) {
    _admitArrivals();
    final anchorAt = rows.indexWhere((row) => row.key == _anchor);
    final split = anchorAt < 0 ? rows.length : anchorAt + 1;
    final chat = ref.read(chatControllerProvider.notifier);
    return Listener(
      onPointerDown: (_) => _pointers++,
      onPointerUp: _onPointerGone,
      onPointerCancel: _onPointerGone,
      child: NotificationListener<Notification>(
        onNotification: _onScrollNotification,
        child: EdgeFade(
          top: AlistenSpacing.md,
          child: CustomScrollView(
            controller: _scroll,
            reverse: true,
            center: _aboveKey,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlistenSpacing.sm,
                ),
                sliver: _RowList(
                  rows: rows.sublist(split),
                  flying: _flying,
                  arrived: _arrived,
                  entering: _entering,
                  onShowEarlier: chat.showEarlier,
                ),
              ),
              SliverPadding(
                key: _aboveKey,
                padding: const EdgeInsets.fromLTRB(
                  AlistenSpacing.sm,
                  AlistenSpacing.md,
                  AlistenSpacing.sm,
                  0,
                ),
                sliver: _RowList(
                  rows: rows.sublist(0, split).reversed.toList(growable: false),
                  flying: _flying,
                  arrived: _arrived,
                  entering: _entering,
                  onShowEarlier: chat.showEarlier,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 下标 0 的行紧挨时间线的固定点。
class _RowList extends StatelessWidget {
  const _RowList({
    required this.rows,
    required this.flying,
    required this.arrived,
    required this.entering,
    required this.onShowEarlier,
  });

  final List<_Row> rows;
  final Map<String, GlobalKey> flying;
  final Set<GlobalKey> arrived;
  final Set<String> entering;
  final VoidCallback onShowEarlier;

  @override
  Widget build(BuildContext context) {
    final indexOf = {
      for (var index = 0; index < rows.length; index++) rows[index].key: index,
    };
    return SliverList.builder(
      itemCount: rows.length,
      findChildIndexCallback: (key) =>
          key is ValueKey<String> ? indexOf[key.value] : null,
      // 自动添加的重绘边界包在 `EdgeFadeItem` 外，滚动时它不会重绘，渐隐会停在
      // 旧位置，所以边界放在它内部。
      addRepaintBoundaries: false,
      itemBuilder: (context, index) {
        final row = rows[index];
        final content = switch (row) {
          _EarlierRow() => Center(
            child: PillButton(
              label: '查看更早的消息',
              icon: AlistenIcons.clockCounterClockwise,
              style: PillButtonStyle.ghost,
              onPressed: onShowEarlier,
            ),
          ),
          // 时间属于它下面那条消息：自己的消息还在飞时不先出来，和头像一起
          // 在到达时淡入。
          _TimeRow(:final at, :final before) => _TimeLabel(
            at: at,
            shown: flying[before] == null || arrived.contains(flying[before]),
          ),
          _MessageRow() => _MessageLine(
            row: row,
            landing: flying[row.key],
            arrived: arrived.contains(flying[row.key]),
          ),
          _ActivityRow(:final item) => _ActivityPill(item: item),
        };
        return EdgeFadeItem(
          key: ValueKey(row.key),
          child: RepaintBoundary(
            child: _Entrance(
              enabled: entering.contains(row.key),
              // 别人的消息从靠头像的左下角冒出；时间和动态只长高、淡入。
              pop: row is _MessageRow && !row.mine,
              onDone: () => entering.remove(row.key),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

sealed class _Row {
  const _Row(this.key);

  /// 行留在时间线上期间保持不变。
  final String key;
}

final class _EarlierRow extends _Row {
  const _EarlierRow() : super('earlier');
}

final class _TimeRow extends _Row {
  _TimeRow(ChatMessageItem next)
    : at = DateTime.fromMillisecondsSinceEpoch(next.sentAtMs),
      before = next.key,
      super('time-${next.key}');

  final DateTime at;

  /// 下面那条消息。
  final String before;
}

final class _MessageRow extends _Row {
  _MessageRow(
    this.item, {
    required this.mine,
    required this.first,
    required this.last,
  }) : super(item.key);

  final ChatMessageItem item;
  final bool mine;

  /// 同一发送者连续消息中只有第一条显示发送者。
  final bool first;
  final bool last;
}

final class _ActivityRow extends _Row {
  _ActivityRow(this.item) : super(item.key);

  final ChatActivityItem item;
}

// [items] 从旧到新。停顿后的消息上方显示时间，动态不单独显示时间。
List<_Row> _rowsOf(
  List<ChatItem> items, {
  required bool hasEarlier,
  required String? self,
}) {
  bool continuesRun(int index) {
    if (index <= 0 || index >= items.length) return false;
    final item = items[index];
    final previous = items[index - 1];
    return item is ChatMessageItem &&
        previous is ChatMessageItem &&
        previous.member.id == item.member.id &&
        item.sentAtMs - previous.sentAtMs <= _runWindowMs;
  }

  final rows = <_Row>[if (hasEarlier) const _EarlierRow()];
  int? lastSentAtMs;
  for (var index = 0; index < items.length; index++) {
    switch (items[index]) {
      case final ChatActivityItem item:
        rows.add(_ActivityRow(item));
      case final ChatMessageItem item:
        if (lastSentAtMs == null || item.sentAtMs - lastSentAtMs > _pauseMs) {
          rows.add(_TimeRow(item));
        }
        rows.add(
          _MessageRow(
            item,
            mine: item.member.id == self,
            first: !continuesRun(index),
            last: !continuesRun(index + 1),
          ),
        );
        lastSentAtMs = item.sentAtMs;
    }
  }
  return rows;
}

/// 放得下成员条、一行输入栏和至少两行消息时才显示成员条；更矮时（如横屏手机、
/// 翻盖手机外屏）高度留给消息和输入栏。
const _stripMinHeight =
    AlistenSizes.minTouchTarget +
    (AlistenSpacing.xs + AlistenSizes.minTouchTarget + AlistenSpacing.sm) +
    2 * AlistenSizes.minTouchTarget;

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.at, required this.shown});

  final DateTime at;
  final bool shown;

  @override
  Widget build(BuildContext context) {
    final label = Padding(
      padding: const EdgeInsets.only(
        top: AlistenSpacing.md,
        bottom: AlistenSpacing.xxs,
      ),
      child: Center(
        child: Text(
          _timeOf(at, DateTime.now()),
          style: AlistenTypography.caption.copyWith(
            color: AlistenColors.of(context).onGlassMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
    return AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: AlistenDurations.of(context, _avatarIn),
      alwaysIncludeSemantics: true,
      child: label,
    );
  }
}

String _timeOf(DateTime at, DateTime now) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final clock = '${twoDigits(at.hour)}:${twoDigits(at.minute)}';
  // 按日历日计算，夏令时切换不会让天数偏移。
  final days = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(at.year, at.month, at.day)).inDays;
  return switch (days) {
    0 => '今天 $clock',
    1 => '昨天 $clock',
    _ when at.year == now.year => '${at.month}月${at.day}日 $clock',
    _ => '${at.year}年${at.month}月${at.day}日 $clock',
  };
}

class _MessageLine extends StatelessWidget {
  const _MessageLine({required this.row, this.landing, this.arrived = false});

  final _MessageRow row;

  /// 不为 null 时，这条消息正从输入框飞过来：气泡和发送状态先藏着、占好位置，
  /// 飞行中的气泡按它的键找到落点，落地停稳后才显出。房间在飞行途中就确认了
  /// 这条消息时也一样。
  final GlobalKey? landing;

  /// 飞行中的气泡已经到过落点：头像这时就淡入，不等气泡停稳。
  final bool arrived;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final _MessageRow(:item, :mine, :first, :last) = row;
    const round = Radius.circular(AlistenRadii.md);
    const joined = Radius.circular(AlistenRadii.joined);
    final top = first ? round : joined;
    final bottom = last ? round : joined;
    final bubble = DecoratedBox(
      key: landing,
      decoration: BoxDecoration(
        color: mine ? colors.brand : colors.bubble,
        borderRadius: mine
            ? BorderRadius.only(
                topLeft: round,
                bottomLeft: round,
                topRight: top,
                bottomRight: bottom,
              )
            : BorderRadius.only(
                topLeft: top,
                bottomLeft: bottom,
                topRight: round,
                bottomRight: round,
              ),
      ),
      child: Padding(
        padding: _bubblePadding,
        // 每条消息单独选择，不跨到相邻消息、名字或时间。触屏上只靠长按开始
        // 选择，不争抢滚动和左右切换模式的拖动。
        child: DefaultSelectionStyle.merge(
          // 主题的选中色取自品牌色，在自己消息的品牌底色上几乎看不出。
          selectionColor: mine ? colors.onBrand.withValues(alpha: 0.35) : null,
          child: SelectionArea(
            child: Text(
              item.text,
              style: AlistenTypography.body.copyWith(
                color: mine ? colors.onBrand : colors.onGlass,
              ),
            ),
          ),
        ),
      ),
    );
    final shown = landing == null
        ? bubble
        : Opacity(opacity: 0, alwaysIncludeSemantics: true, child: bubble);
    // 头像在飞行气泡到达时就淡入，不凭空冒出来，也不等它停稳。
    final avatar = AnimatedOpacity(
      opacity: landing == null || arrived ? 1 : 0,
      duration: AlistenDurations.of(context, _avatarIn),
      child: SizedBox(
        width: AlistenSizes.avatar,
        child: first
            ? MemberAvatar(
                name: item.member.name,
                imageUrl: item.member.avatarUrl,
              )
            : null,
      ),
    );
    final content = Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (first && !mine)
            Padding(
              padding: const EdgeInsets.only(
                left: AlistenSpacing.xxs,
                bottom: AlistenSpacing.xxs,
              ),
              child: ExcludeSemantics(
                child: Text(
                  item.member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlassMuted,
                  ),
                ),
              ),
            ),
          if (mine && item.delivery != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (landing == null) ...[
                  _DeliveryMark(item: item),
                  const SizedBox(width: AlistenSpacing.xxs),
                ],
                Flexible(child: shown),
              ],
            )
          else
            shown,
          if (mine && item.note != null && landing == null)
            Padding(
              padding: const EdgeInsets.only(
                top: AlistenSpacing.xxs,
                right: AlistenSpacing.xxs,
              ),
              child: Text(
                item.note!,
                textAlign: TextAlign.end,
                style: AlistenTypography.secondary.copyWith(
                  color: colors.danger,
                ),
              ),
            ),
        ],
      ),
    );
    const gap = SizedBox(width: AlistenSpacing.xs);
    const gutter = SizedBox(width: _farGutter);
    return Padding(
      padding: EdgeInsets.only(
        top: first ? AlistenSpacing.sm : AlistenSpacing.xxs,
      ),
      child: MergeSemantics(
        child: Semantics(
          label: mine ? '我' : item.member.name,
          child: Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: mine
                ? [gutter, content, gap, avatar]
                : [avatar, gap, content, gutter],
          ),
        ),
      ),
    );
  }
}

class _ActivityPill extends StatelessWidget {
  const _ActivityPill({required this.item});

  final ChatActivityItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final failed = item.kind == RoomActivityKind.failed;
    final icon = switch (item.kind) {
      RoomActivityKind.added => AlistenIcons.listPlus,
      RoomActivityKind.removed => AlistenIcons.listDashes,
      RoomActivityKind.liked => AlistenIcons.heartFill,
      RoomActivityKind.voted => AlistenIcons.checkSquare,
      RoomActivityKind.skipped => AlistenIcons.skipForwardFill,
      RoomActivityKind.failed => AlistenIcons.warningCircle,
    };
    final actor = item.member;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlistenSpacing.xl,
        vertical: AlistenSpacing.xs,
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.glassFill,
            borderRadius: BorderRadius.circular(AlistenRadii.pill),
            border: Border.all(color: colors.glassStroke),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AlistenSpacing.sm,
              AlistenSpacing.xxs,
              AlistenSpacing.md,
              AlistenSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: AlistenSizes.inlineIcon,
                  color: failed
                      ? colors.danger
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AlistenSpacing.xs),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (actor != null)
                          TextSpan(
                            text: '${actor.name} ',
                            style: TextStyle(color: colors.onGlass),
                          ),
                        TextSpan(text: item.message),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AlistenTypography.weighted(
                      AlistenTypography.secondary,
                      FontWeight.w600,
                    ).copyWith(color: colors.onGlassMuted),
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

class _ToLatestButton extends ConsumerWidget {
  const _ToLatestButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final away = ref.watch(
      chatControllerProvider.select((chat) => !chat.atBottom),
    );
    final unread = ref.watch(
      chatControllerProvider.select((chat) => chat.unread),
    );
    return AnimatedSwitcher(
      duration: AlistenDurations.of(context, AlistenDurations.short),
      switchInCurve: AlistenCurves.standard,
      switchOutCurve: AlistenCurves.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: !away
          ? const SizedBox.shrink()
          : _FloatingChip(
              key: ValueKey(unread > 0),
              label: unread > 0 ? '新消息 $unread 条' : '回到最新',
              accent: unread > 0,
              onPressed: onPressed,
            ),
    );
  }
}

/// 浮在消息上面的小卡片。用面板的底色、描边和阴影，不用品牌色：自己的气泡
/// 就是品牌色，同色的按钮叠在上面分不出来。
class _FloatingChip extends StatelessWidget {
  const _FloatingChip({
    required this.label,
    required this.accent,
    required this.onPressed,
    super.key,
  });

  final String label;

  /// 有新消息时文字用品牌色。
  final bool accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final ink = accent ? colors.brand : colors.onGlass;
    final shape = BorderRadius.circular(AlistenRadii.pill);
    return Pressable(
      onPressed: onPressed,
      focusRadius: shape,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.raised,
          borderRadius: shape,
          border: Border.all(color: colors.glassStroke),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow
                  .withValues(alpha: 0.16),
              blurRadius: AlistenSpacing.md,
              offset: const Offset(0, AlistenSpacing.xxs),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AlistenSizes.minTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AlistenIcons.arrowDown,
                  size: AlistenSizes.iconSm,
                  color: ink,
                ),
                const SizedBox(width: AlistenSpacing.xs),
                Text(
                  label,
                  style: AlistenTypography.weighted(
                    AlistenTypography.secondary,
                    FontWeight.w700,
                  ).copyWith(color: ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.onSend});

  /// 开始发送时即调用，不等发送结果：带上本地消息的行键和发送那一刻的输入框，
  /// 没能发出时都为 null。返回输入框是否飞了出去，飞了就换上新的空输入框。
  final bool Function(String? key, FlightSource? source) onSend;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _input;
  final _focus = FocusNode();
  final _field = GlobalKey();

  // 输入框飞出去之后，原处的新输入框从这里开始重新出现；键盘和焦点一直留着。
  late final _comeback = AnimationController(
    vsync: this,
    duration: _fieldReturn,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(
      text: ref.read(chatControllerProvider).draft,
    );
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _comeback.dispose();
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _input.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  // Gboard 等输入法输入英文单词时，按空格前都处于组词状态。
  bool get _composing {
    final composing = _input.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  // 先提交仍在组的词再发送全文，与常见聊天应用一致，不拦下这条消息。
  void _send() {
    if (_composing) _input.clearComposing();
    final chat = ref.read(chatControllerProvider.notifier)
      ..setDraft(_input.text);
    final state = ref.read(chatControllerProvider);
    final connected =
        ref.read(roomControllerProvider).status == RoomConnectionStatus.open;
    if (!connected || state.draft.trim().isEmpty) return;
    // 草稿清空之前量好文字的位置，飞行从那里开始。
    final source = flightSourceOf(
      _field.currentContext?.findRenderObject(),
      text: _input.text,
    );
    final waiting = state.pending.length;
    unawaited(chat.send());
    final pending = ref.read(chatControllerProvider).pending;
    final sent = pending.length > waiting;
    final flew = widget.onSend(
      sent ? pending.last.key : null,
      sent ? source : null,
    );
    if (flew) unawaited(_comeback.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final draft = ref.watch(
      chatControllerProvider.select((chat) => chat.draft),
    );
    final sendError = ref.watch(
      chatControllerProvider.select((chat) => chat.sendError),
    );
    final connected = ref.watch(
      roomControllerProvider.select(
        (room) => room.status == RoomConnectionStatus.open,
      ),
    );
    // 控制器在消息确认后清空草稿，输入框须同步。
    ref.listen(chatControllerProvider.select((chat) => chat.draft), (_, draft) {
      if (_input.text == draft) return;
      _input.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    });
    final canSend = connected && draft.trim().isNotEmpty;
    final left = chatMessageLimit - draft.trim().runes.length;
    final textStyle = AlistenTypography.body.copyWith(color: colors.onGlass);
    final field = DecoratedBox(
      key: _field,
      decoration: BoxDecoration(
        color: colors.glassFill,
        borderRadius: BorderRadius.circular(AlistenRadii.lg),
        border: Border.all(
          color: _focus.hasFocus ? colors.outline : colors.glassStroke,
        ),
      ),
      child: TextField(
        controller: _input,
        focusNode: _focus,
        minLines: 1,
        maxLines: 5,
        // 纯文本键盘才有发送键；长文本自动折行。
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.send,
        style: textStyle,
        // iOS 默认光标淡入淡出，聚焦期间按刷新率持续出帧；改为每 500 ms 闪烁
        // 一次，与 Android 一致。
        cursorOpacityAnimates: false,
        textAlignVertical: TextAlignVertical.center,
        // 留白属于输入框本身：点按留白也能聚焦，读屏触控区域覆盖整个框。
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AlistenSpacing.md,
            vertical: AlistenSpacing.sm,
          ),
          constraints: const BoxConstraints(
            minHeight: AlistenSizes.minTouchTarget,
          ),
          border: InputBorder.none,
          hintText: '说点什么…',
          hintStyle: textStyle.copyWith(color: colors.onGlassMuted),
        ),
        onChanged: ref.read(chatControllerProvider.notifier).setDraft,
        // 提交组词并保持焦点，键盘留着输入下一条；默认行为会让输入框失焦。
        onEditingComplete: _input.clearComposing,
        onSubmitted: (_) => _send(),
      ),
    );
    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AlistenSpacing.sm,
          AlistenSpacing.xs,
          AlistenSpacing.sm,
          AlistenSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedResize(
              duration: AlistenDurations.of(context, AlistenDurations.short),
              curve: AlistenCurves.standard,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 不朗读：房间顶栏会播报连接状态。
                  if (!connected)
                    _ComposerNotice(
                      icon: AlistenIcons.cloudSlash,
                      text: '连接后可发送',
                      color: colors.warning,
                    ),
                  if (sendError != null)
                    _ComposerNotice(
                      icon: AlistenIcons.warningCircle,
                      text: sendError,
                      color: colors.danger,
                      announce: true,
                    ),
                  if (left < chatMessageLimit - _lengthHintFrom)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AlistenSpacing.xs,
                        0,
                        AlistenSpacing.xs,
                        AlistenSpacing.xs,
                      ),
                      child: Text(
                        left < 0 ? '超出 ${-left} 字' : '还能输入 $left 字',
                        textAlign: TextAlign.end,
                        style: AlistenTypography.secondary.copyWith(
                          color: left < 0 ? colors.danger : colors.onGlassMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation: _comeback,
                    child: field,
                    builder: (context, field) {
                      final back = _fieldReturnMove.transform(_comeback.value);
                      return Opacity(
                        opacity: back,
                        alwaysIncludeSemantics: true,
                        child: Transform.scale(
                          scale: lerpDouble(_fieldReturnScale, 1, back),
                          child: field,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: AlistenSpacing.xs),
                _SendButton(onPressed: canSend ? _send : null),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerNotice extends StatelessWidget {
  const _ComposerNotice({
    required this.icon,
    required this.text,
    required this.color,
    this.announce = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool announce;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: announce,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AlistenSpacing.xs,
          0,
          AlistenSpacing.xs,
          AlistenSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: AlistenSizes.inlineIcon, color: color),
            const SizedBox(width: AlistenSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: AlistenTypography.secondary.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    const size = AlistenSizes.minTouchTarget;
    // 不能发送时换成玻璃底，而不是整体变暗：变暗的封面色在深色房间里发浑。
    final idle = onPressed == null;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: '发送',
      dimWhenDisabled: false,
      hoverColor: idle ? null : colors.onBrand,
      focusRadius: BorderRadius.circular(size / 2),
      child: AnimatedContainer(
        duration: AlistenDurations.of(context, AlistenDurations.short),
        curve: AlistenCurves.standard,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: idle ? colors.glassFill : colors.brand,
          border: Border.all(color: idle ? colors.glassStroke : colors.brand),
        ),
        child: Icon(
          AlistenIcons.arrowUpBold,
          size: AlistenSizes.icon,
          color: idle ? colors.onGlassMuted : colors.onBrand,
        ),
      ),
    );
  }
}

/// 自己的消息还没出现在房间时间线上时，气泡旁的标记：发送中转圈；没发出或
/// 结果未知时是红色的叹号，点开可以重发或删除。
class _DeliveryMark extends ConsumerWidget {
  const _DeliveryMark({required this.item});

  final ChatMessageItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    final chat = ref.read(chatControllerProvider.notifier);
    return switch (item.delivery) {
      ChatDelivery.sending => BusyIndicator(
        size: AlistenSizes.inlineIcon,
        color: colors.onGlassMuted,
        semanticLabel: '发送中',
      ),
      ChatDelivery.failed || ChatDelivery.unknown => ActionMenuButton(
        semanticLabel: '没有发出，重发或删除',
        trigger: (open, toggle) => Pressable(
          onPressed: toggle,
          semanticLabel: '没有发出，重发或删除',
          expanded: open,
          focusRadius: BorderRadius.circular(AlistenSizes.iconSm),
          child: Padding(
            padding: const EdgeInsets.all(AlistenSpacing.xxs),
            child: Icon(
              AlistenIcons.warningCircleFill,
              size: AlistenSizes.iconSm,
              color: colors.danger,
            ),
          ),
        ),
        entries: [
          ActionMenuEntry(
            icon: AlistenIcons.arrowClockwise,
            label: '重发',
            onSelected: () => unawaited(chat.retry(item.key)),
          ),
          ActionMenuEntry(
            icon: AlistenIcons.trash,
            label: '删除',
            danger: true,
            onSelected: () => chat.discard(item.key),
          ),
        ],
      ),
      ChatDelivery.sent || null => const SizedBox.shrink(),
    };
  }
}

class _Entrance extends StatefulWidget {
  const _Entrance({
    required this.enabled,
    required this.pop,
    required this.onDone,
    required this.child,
  });

  /// 只在行刚建好时读：已经在时间线上的行不会再做一遍。
  final bool enabled;
  final bool pop;
  final VoidCallback onDone;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _clock;
  late final _bounce = SpringCurve(
    AlistenSprings.chatFlight,
    seconds: _entrance.inMicroseconds / Duration.microsecondsPerSecond,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    _clock = AnimationController(vsync: this, duration: _entrance);
    unawaited(
      _clock!.forward().whenComplete(() {
        if (mounted) widget.onDone();
      }),
    );
  }

  // 还没长完就滚出了视野、被回收时也算做过了，滚回来不再做一遍。
  @override
  void dispose() {
    final clock = _clock;
    if (clock != null && !clock.isCompleted) widget.onDone();
    clock?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clock = _clock;
    if (clock == null) return widget.child;
    return AnimatedBuilder(
      animation: clock,
      child: widget.child,
      builder: (context, child) {
        final t = clock.value;
        final grown = _entranceGrow.transform(t);
        final scale = widget.pop
            ? lerpDouble(_entranceScale, 1, _bounce.transform(t))!
            : 1.0;
        // 长到原高之前裁掉露在下面的部分；之后不裁，落定时的轻弹不被切掉。
        return ClipRect(
          clipBehavior: grown < 1 ? Clip.hardEdge : Clip.none,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: math.max(grown, _entranceLeast),
            child: Opacity(
              opacity: _entranceFade.transform(t),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.bottomLeft,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
