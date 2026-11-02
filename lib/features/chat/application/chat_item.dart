import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';

sealed class ChatItem {
  const ChatItem({required this.key});

  /// 在房间内唯一，重建时保持不变。
  final String key;
}

final class ChatMessageItem extends ChatItem {
  const ChatMessageItem({
    required super.key,
    required this.member,
    required this.text,
    required this.sentAtMs,
  });

  final Member member;
  final String text;
  final int sentAtMs;
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
