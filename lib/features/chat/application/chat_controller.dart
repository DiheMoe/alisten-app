import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/chat/application/chat_item.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 按 Unicode 字符（rune）计数而非 UTF-16 码元；服务端会截断超出部分。
const chatMessageLimit = 500;
const _earlierBatch = 80;
const _contentTooLong = '消息不能超过 500 字';
const _sendingAlready = '上一条消息还在发送。';
const _emptyMessage = '消息不能为空。';
const _unknownDelivery = '消息发送结果未知，请核对房间消息后再操作。';

final class ChatState {
  const ChatState({
    this.messages = const [],
    this.visibleCount = _earlierBatch,
    this.draft = '',
    this.sending = false,
    this.sendError,
    this.atBottom = true,
    this.unread = 0,
    this.failureNotice,
    this.failureNoticeId = 0,
  });

  /// 最新的在最后；进入另一个房间时清空。
  final List<ChatItem> messages;
  final int visibleCount;

  /// 放在控制器中，离开页面后仍保留。
  final String draft;
  final bool sending;
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
    int? visibleCount,
    String? draft,
    bool? sending,
    Object? sendError = _unchanged,
    bool? atBottom,
    int? unread,
    String? failureNotice,
    int? failureNoticeId,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      visibleCount: visibleCount ?? this.visibleCount,
      draft: draft ?? this.draft,
      sending: sending ?? this.sending,
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

  /// 只有服务端确认送达且草稿期间未被改动时才清空草稿，其他结果都保留草稿。
  Future<MutationResult<void>> send() async {
    if (state.sending) return const MutationNotSent(_sendingAlready);
    final sent = state.draft;
    final content = sent.trim();
    if (content.isEmpty) return const MutationNotSent(_emptyMessage);
    if (content.runes.length > chatMessageLimit) {
      state = state.copyWith(sendError: _contentTooLong);
      return const MutationNotSent(_contentTooLong);
    }
    final epoch = _epoch;
    state = state.copyWith(sending: true, sendError: null);
    final result = await ref
        .read(roomControllerProvider.notifier)
        .mutate((c) => c.sendChat(content));
    if (!ref.mounted || epoch != _epoch) return result;
    final error = switch (result) {
      MutationSucceeded() => null,
      MutationUnknown() => _unknownDelivery,
      MutationFailed(:final message) ||
      MutationNotSent(:final message) => message,
    };
    state = state.copyWith(
      sending: false,
      sendError: error,
      draft: error == null && state.draft.trim() == content ? '' : null,
    );
    return result;
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
