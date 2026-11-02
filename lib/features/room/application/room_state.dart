import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';

enum RoomFailure { authorization, notFound, outdated, unavailable }

sealed class RoomJoin {
  const RoomJoin();
}

/// 只表示房间已成为当前房间，不代表连接已打开；连接状态见 [RoomState]。
final class RoomJoined extends RoomJoin {
  const RoomJoined(this.room);

  final RoomListing room;
}

/// 被新请求取代时以 [RoomFailure.unavailable] 结束。
final class RoomJoinFailed extends RoomJoin {
  const RoomJoinFailed(this.failure, this.message, {this.room});

  final RoomFailure failure;
  final String message;
  final RoomListing? room;
}

/// [snapshot]、[member] 和 [notices] 按引用比较：所有者只在它们变化时替换，
/// 因此状态相等即无变化，不通知监听者。
final class RoomState {
  const RoomState({
    this.status = RoomConnectionStatus.stopped,
    this.nextRetryAt,
    this.activeRoomId,
    this.roomName,
    this.roomSlug,
    this.snapshot,
    this.member,
    this.failure,
    this.errorMessage,
    this.notices = const [],
    this.liveUpdate = false,
    this.mayReconnectNow = true,
  });

  final RoomConnectionStatus status;
  final DateTime? nextRetryAt;

  /// 每次断线只允许立即重连一次，避免反复检查连接时不停重试连不上的服务端；
  /// 网络变化、回到前台、收到握手回复和进入房间时重新允许。
  final bool mayReconnectNow;

  final String? activeRoomId;

  /// 快照清空后仍保留，房间停止后还能显示名字。
  final String? roomName;
  final String? roomSlug;
  final RoomSnapshot? snapshot;
  final Member? member;
  final RoomFailure? failure;
  final String? errorMessage;

  /// 聊天消息和房间动态，最新的在最后。
  final List<RoomEvent> notices;

  /// 快照最近一次变化是否来自实时房间事件，而非握手回复或同步。
  final bool liveUpdate;

  RoomState copyWith({
    RoomConnectionStatus? status,
    Object? nextRetryAt = _unchanged,
    Object? activeRoomId = _unchanged,
    Object? roomName = _unchanged,
    Object? snapshot = _unchanged,
    Object? member = _unchanged,
    Object? failure = _unchanged,
    Object? errorMessage = _unchanged,
    List<RoomEvent>? notices,
    bool? liveUpdate,
    bool? mayReconnectNow,
  }) {
    return RoomState(
      status: status ?? this.status,
      nextRetryAt: identical(nextRetryAt, _unchanged)
          ? this.nextRetryAt
          : nextRetryAt as DateTime?,
      activeRoomId: identical(activeRoomId, _unchanged)
          ? this.activeRoomId
          : activeRoomId as String?,
      roomName: identical(roomName, _unchanged)
          ? this.roomName
          : roomName as String?,
      roomSlug: roomSlug,
      snapshot: identical(snapshot, _unchanged)
          ? this.snapshot
          : snapshot as RoomSnapshot?,
      member: identical(member, _unchanged) ? this.member : member as Member?,
      failure: identical(failure, _unchanged)
          ? this.failure
          : failure as RoomFailure?,
      errorMessage: identical(errorMessage, _unchanged)
          ? this.errorMessage
          : errorMessage as String?,
      notices: notices ?? this.notices,
      liveUpdate: liveUpdate ?? this.liveUpdate,
      mayReconnectNow: mayReconnectNow ?? this.mayReconnectNow,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RoomState &&
        other.status == status &&
        other.nextRetryAt == nextRetryAt &&
        other.activeRoomId == activeRoomId &&
        other.roomName == roomName &&
        other.roomSlug == roomSlug &&
        identical(other.snapshot, snapshot) &&
        identical(other.member, member) &&
        other.failure == failure &&
        other.errorMessage == errorMessage &&
        identical(other.notices, notices) &&
        other.liveUpdate == liveUpdate &&
        other.mayReconnectNow == mayReconnectNow;
  }

  @override
  int get hashCode => Object.hash(
    status,
    nextRetryAt,
    activeRoomId,
    roomName,
    roomSlug,
    identityHashCode(snapshot),
    identityHashCode(member),
    failure,
    errorMessage,
    identityHashCode(notices),
    liveUpdate,
    mayReconnectNow,
  );
}

const _unchanged = Object();
