import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';

sealed class ChatItem {
  const ChatItem({required this.key});

  /// 在房间内唯一，重建时保持不变。
  final String key;
}

/// 自己发出、还没在房间时间线上出现的消息走到了哪一步。
enum ChatDelivery {
  sending,

  /// 服务端已确认收到，等它广播回来。
  sent,

  /// 没有发出去，原因在 [ChatMessageItem.note]。
  failed,

  /// 发出后连接断了，不知道房间有没有收到。
  unknown,
}

final class ChatMessageItem extends ChatItem {
  const ChatMessageItem({
    required super.key,
    required this.member,
    required this.text,
    required this.sentAtMs,
    this.delivery,
    this.note,
  });

  final Member member;
  final String text;
  final int sentAtMs;

  /// 为 null 时消息已在房间的时间线上。
  final ChatDelivery? delivery;

  /// 没发出去或结果未知的原因。
  final String? note;

  ChatMessageItem withDelivery(ChatDelivery delivery, {String? note}) =>
      ChatMessageItem(
        key: key,
        member: member,
        text: text,
        sentAtMs: sentAtMs,
        delivery: delivery,
        note: note,
      );
}

final class ChatActivityItem extends ChatItem {
  const ChatActivityItem({
    required super.key,
    required this.kind,
    required this.message,
    this.member,
  });

  final RoomActivityKind kind;

  /// 准备失败和自动加入的动态没有执行者。
  final Member? member;

  /// 不含执行者，服务端将其写成句子的谓语部分。
  final String message;

  String get text {
    final actor = member;
    return actor == null ? message : '${actor.name} $message';
  }
}

ChatItem? chatItemOf(RoomEvent event) {
  final key = '${event.term}:${event.seq}';
  return switch (event) {
    ChatMessageEvent() => ChatMessageItem(
      key: key,
      member: event.member,
      text: event.content,
      sentAtMs: event.sentAtMs,
    ),
    RoomActivityEvent() => ChatActivityItem(
      key: key,
      kind: event.kind,
      member: event.member,
      message: event.message,
    ),
    _ => null,
  };
}
