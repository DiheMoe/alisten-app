import 'dart:math' as math;

import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/chat/application/chat_item.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 按 Unicode 字符（rune）计数而非 UTF-16 码元；服务端会截断超出部分。
const chatMessageLimit = 500;
const _earlierBatch = 80;
const _contentTooLong = '消息不能超过 500 字';
const _emptyMessage = '消息不能为空。';
const _unknownDelivery = '发送结果未知，房间里没有这条再重发。';
const _notInRoom = '还没有进入房间。';
const _alreadyGoing = '这条消息已经在发送。';

// 记住最近这么多条本地消息换成了哪条房间消息，飞行中的气泡据此找到落点。
const _confirmedMemory = 20;

final class ChatState {
  ChatState({
    this.messages = const [],
    this.pending = const [],
    this.visibleCount = _earlierBatch,
    this.draft = '',
    this.sendError,
    this.atBottom = true,
    this.unread = 0,
    this.failureNotice,
    this.failureNoticeId = 0,
    List<ChatItem>? timeline,
  }) : timeline =
           timeline ?? (pending.isEmpty ? messages : [...messages, ...pending]);

  /// 房间时间线上的行，最新的在最后；进入另一个房间时清空。
  final List<ChatItem> messages;

  /// 自己发出、还没在房间时间线上出现的消息，按发出顺序。
  final List<ChatMessageItem> pending;

  /// [messages] 后面接着 [pending]，就是显示出来的时间线。两者都没变时保持
  /// 同一个对象，监听它的界面不会白白重建。
  final List<ChatItem> timeline;

  final int visibleCount;

  /// 放在控制器中，离开页面后仍保留。
  final String draft;

  /// 还没发出就被拦下的原因，比如超长；发出后的失败记在消息上。
  final String? sendError;
  final bool atBottom;

  /// 时间线不在底部期间新到的行数。
  final int unread;

  /// 自己点的歌准备失败的原因。[failureNoticeId] 每次失败都会变化，使相同的
  /// 文字也会再次播报。
  final String? failureNotice;
  final int failureNoticeId;

  ChatState copyWith({
    List<ChatItem>? messages,
    List<ChatMessageItem>? pending,
    int? visibleCount,
    String? draft,
    Object? sendError = _unchanged,
    bool? atBottom,
    int? unread,
    String? failureNotice,
    int? failureNoticeId,
  }) {
    final nextMessages = messages ?? this.messages;
    final nextPending = pending ?? this.pending;
    return ChatState(
      messages: nextMessages,
      pending: nextPending,
      timeline:
          identical(nextMessages, this.messages) &&
              identical(nextPending, this.pending)
          ? timeline
          : null,
      visibleCount: visibleCount ?? this.visibleCount,
      draft: draft ?? this.draft,
      sendError: identical(sendError, _unchanged)
          ? this.sendError
          : sendError as String?,
      atBottom: atBottom ?? this.atBottom,
      unread: unread ?? this.unread,
      failureNotice: failureNotice ?? this.failureNotice,
      failureNoticeId: failureNoticeId ?? this.failureNoticeId,
    );
  }
}

const _unchanged = Object();

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

final class ChatController extends Notifier<ChatState> {
  String? _roomId;
  ({int term, int seq})? _newest;
  // 递增即丢弃已离开房间的发送结果。
  int _epoch = 0;
  int _localSeq = 0;
  final _confirmed = <String, String>{};

  @override
  ChatState build() {
    final room = ref.read(roomControllerProvider);
    ref.listen<RoomState>(roomControllerProvider, _onRoom);
    return _initial(room);
  }

  ChatState _initial(RoomState room) {
    _epoch++;
    _roomId = room.activeRoomId;
    _newest = _positionOf(room.notices.lastOrNull);
    return ChatState(
      messages: [for (final notice in room.notices) ?chatItemOf(notice)],
    );
  }

  void _onRoom(RoomState? previous, RoomState next) {
    if (_roomId != next.activeRoomId) {
      state = _initial(next);
      return;
    }
    if (identical(previous?.notices, next.notices)) return;
    final fresh = _freshNotices(next.notices);
    if (fresh.isEmpty) return;
    _newest = _positionOf(fresh.last);
    final items = [
      ...state.messages,
      for (final notice in fresh) ?chatItemOf(notice),
    ];
    final kept = items.length > next.notices.length
        ? items.sublist(items.length - next.notices.length)
        : items;
    final failure = _ownFailure(fresh, next);
    state = state.copyWith(
      messages: kept,
      pending: _withoutEchoes(fresh, next.member?.id),
      unread: state.atBottom ? null : state.unread + fresh.length,
      failureNotice: failure?.message,
      failureNoticeId: failure == null ? null : state.failureNoticeId + 1,
    );
  }

  // 通知按事件顺序排列，只需从列表末尾向前查找。
  List<RoomEvent> _freshNotices(List<RoomEvent> notices) {
    final newest = _newest;
    var first = notices.length;
    while (first > 0 && _isAfter(notices[first - 1], newest)) {
      first--;
    }
    return notices.sublist(first);
  }

  /// 房间广播回来的自己的消息替换掉对应的本地消息：按发出顺序，取内容相同的
  /// 第一条。没发出去的不算，它们不会出现在房间里。
  List<ChatMessageItem> _withoutEchoes(List<RoomEvent> fresh, String? self) {
    if (self == null || state.pending.isEmpty) return state.pending;
    final left = [...state.pending];
    for (final event in fresh) {
      if (event is! ChatMessageEvent || event.member.id != self) continue;
      final match = left.indexWhere(
        (item) =>
            item.delivery != ChatDelivery.failed && item.text == event.content,
      );
      if (match < 0) continue;
      _remember(left.removeAt(match).key, '${event.term}:${event.seq}');
    }
    return left.length == state.pending.length ? state.pending : left;
  }

  void _remember(String local, String confirmed) {
    _confirmed[local] = confirmed;
    if (_confirmed.length > _confirmedMemory) {
      _confirmed.remove(_confirmed.keys.first);
    }
  }

  /// 本地消息 [local] 被房间广播回来后的行键。
  String? confirmedAs(String local) => _confirmed[local];

  // 服务端在失败动态中不带成员，要按条目的点歌人判断是不是自己点的歌。
  RoomActivityEvent? _ownFailure(List<RoomEvent> fresh, RoomState room) {
    final self = room.member?.id;
    if (self == null) return null;
    for (final event in fresh.reversed) {
      if (event is RoomActivityEvent &&
          event.kind == RoomActivityKind.failed &&
          event.entry?.requestedBy?.id == self) {
        return event;
      }
    }
    return null;
  }

  /// 同时清除上次发送的错误，因为它针对的是修改前的文字。
  void setDraft(String draft) {
    if (draft == state.draft) return;
    state = state.copyWith(draft: draft, sendError: null);
  }

  void showEarlier() {
    state = state.copyWith(visibleCount: state.visibleCount + _earlierBatch);
  }

  /// 每次滚动都会调用，值不变时不得通知监听者。
  void setAtBottom(bool atBottom) {
    if (atBottom == state.atBottom) return;
    state = state.copyWith(atBottom: atBottom, unread: atBottom ? 0 : null);
  }

  void markRead() {
    if (state.unread == 0) return;
    state = state.copyWith(unread: 0);
  }

  /// 消息立刻接在时间线末尾、草稿清空，不等上一条的结果；结果记在这条消息上。
  Future<MutationResult<void>> send() async {
    final content = state.draft.trim();
    if (content.isEmpty) return const MutationNotSent(_emptyMessage);
    if (content.runes.length > chatMessageLimit) {
      state = state.copyWith(sendError: _contentTooLong);
      return const MutationNotSent(_contentTooLong);
    }
    final self = ref.read(roomControllerProvider).member;
    if (self == null) return const MutationNotSent(_notInRoom);
    final newest = state.messages.whereType<ChatMessageItem>().lastOrNull;
    final item = ChatMessageItem(
      key: 'local-${++_localSeq}',
      member: self,
      text: content,
      // 本机时间可能比房间慢，不排到已有消息之前。
      sentAtMs: math.max(
        DateTime.now().millisecondsSinceEpoch,
        newest?.sentAtMs ?? 0,
      ),
      delivery: ChatDelivery.sending,
    );
    state = state.copyWith(
      draft: '',
      sendError: null,
      pending: [...state.pending, item],
    );
    return _deliver(item);
  }

  /// 再发一次没发出去或结果未知的消息。
  Future<MutationResult<void>> retry(String key) async {
    final item = state.pending.where((item) => item.key == key).firstOrNull;
    if (item == null ||
        item.delivery == ChatDelivery.sending ||
        item.delivery == ChatDelivery.sent) {
      return const MutationNotSent(_alreadyGoing);
    }
    _mark(key, ChatDelivery.sending);
    return _deliver(item);
  }

  void discard(String key) {
    final left = [
      for (final item in state.pending)
        if (item.key != key) item,
    ];
    if (left.length != state.pending.length) {
      state = state.copyWith(pending: left);
    }
  }

  Future<MutationResult<void>> _deliver(ChatMessageItem item) async {
    final epoch = _epoch;
    final result = await ref
        .read(roomControllerProvider.notifier)
        .mutate((c) => c.sendChat(item.text));
    if (!ref.mounted || epoch != _epoch) return result;
    switch (result) {
      case MutationSucceeded():
        _mark(item.key, ChatDelivery.sent);
      case MutationUnknown():
        _mark(item.key, ChatDelivery.unknown, note: _unknownDelivery);
      case MutationFailed(:final message) || MutationNotSent(:final message):
        _mark(item.key, ChatDelivery.failed, note: message);
    }
    return result;
  }

  // 房间已经广播回来的消息不在 pending 里，不再改。
  void _mark(String key, ChatDelivery delivery, {String? note}) {
    final at = state.pending.indexWhere((item) => item.key == key);
    if (at < 0) return;
    state = state.copyWith(
      pending: [...state.pending]
        ..[at] = state.pending[at].withDelivery(delivery, note: note),
    );
  }
}

({int term, int seq})? _positionOf(RoomEvent? event) {
  return event == null ? null : (term: event.term, seq: event.seq);
}

bool _isAfter(RoomEvent event, ({int term, int seq})? position) {
  return position == null ||
      event.term > position.term ||
      (event.term == position.term && event.seq > position.seq);
}
