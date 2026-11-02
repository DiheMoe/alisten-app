import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/clock/server_clock.dart';
import 'package:alisten/core/protocol/protocol.gen.dart' show RoomRequestTypes;
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';

enum RoomConnectionStatus { connecting, open, reconnecting, stopped }

/// 请求失败时已知的结果。
///
/// `notSent`：请求没有写入连接，可以重试。
/// `failed`：请求没有生效：被服务端拒绝，或是没有得到可用回复的读取请求。
/// `unknown`：变更请求已写入连接，但没有得到确定的回复（超时、断线、
/// 退出房间、`UNAVAILABLE`、`INTERNAL` 或回复无法解码）。它可能已经生效，
/// 不得重发；同步房间后才能知道结果。
enum RoomRequestOutcome { notSent, failed, unknown }

final class RoomRequestException implements Exception {
  const RoomRequestException({
    required this.message,
    required this.outcome,
    this.code,
  });

  factory RoomRequestException.undecodable(String type) {
    final read = isReadRequest(type);
    return RoomRequestException(
      code: LocalErrorCodes.protocolMismatch,
      message: read
          ? '服务器返回了无法识别的结果，请升级 Alisten。'
          : '服务器返回了无法识别的结果，操作结果未知，请升级 Alisten。',
      outcome: read ? RoomRequestOutcome.failed : RoomRequestOutcome.unknown,
    );
  }

  /// 协议 `ErrorCode` 的取值；回复无法解码时为 `PROTOCOL_MISMATCH`，没有收到
  /// 回复时为 null。
  final String? code;
  final String message;
  final RoomRequestOutcome outcome;

  @override
  String toString() => message;
}

const _readRequestTypes = {
  RoomRequestTypes.roomSync,
  RoomRequestTypes.searchTracks,
  RoomRequestTypes.searchPlaylists,
  RoomRequestTypes.playlistTracks,
  RoomRequestTypes.recommendList,
};

/// 其余请求类型，包括协议以后新增的类型，一律按变更请求处理。
bool isReadRequest(String type) => _readRequestTypes.contains(type);

final class RoomHello {
  const RoomHello({required this.member, required this.room});

  final Member member;
  final RoomSnapshot room;
}

sealed class RoomTransportEvent {
  const RoomTransportEvent();
}

final class RoomConnectionChanged extends RoomTransportEvent {
  const RoomConnectionChanged(this.status, {this.retryIn});

  final RoomConnectionStatus status;
  final Duration? retryIn;
}

final class RoomHelloReceived extends RoomTransportEvent {
  const RoomHelloReceived(this.hello);

  final RoomHello hello;
}

final class RoomEventReceived extends RoomTransportEvent {
  const RoomEventReceived(this.event);

  final RoomEvent event;
}

final class RoomErrorReceived extends RoomTransportEvent {
  const RoomErrorReceived({required this.code, required this.message});

  final String code;
  final String message;
}

final class RoomStopped extends RoomTransportEvent {
  const RoomStopped(this.code);

  final int code;
}

abstract interface class RoomTransport {
  Stream<RoomTransportEvent> get events;

  ServerClock get clock;

  Future<void> start();

  /// 失败时抛出 [RoomRequestException]；不会自动重发。
  Future<Map<String, Object?>> request(String type, Map<String, Object?> data);

  /// 等待重连时立即连接；正在建立或已打开的连接不受影响。
  void check();

  /// [deadline] 内没有收到任何帧就断开并重连。没有已打开的连接时
  /// 与 [check] 相同。
  void probe(Duration deadline);

  /// 断开已打开的连接，按正常退避重连（之后调用 [check] 会立即连接）；
  /// 连接打开之前不做任何事。
  void restart();

  /// 永久结束连接，让等待中的请求失败（读取请求为 `failed`，变更请求为
  /// `unknown`），并关闭 [events]。
  Future<void> stop();
}
