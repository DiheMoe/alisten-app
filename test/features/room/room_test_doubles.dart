import 'dart:async';

import 'package:alisten/core/clock/server_clock.dart';
import 'package:alisten/core/protocol/protocol.gen.dart' show RoomRequestTypes;
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/core/realtime/reconnect_policy.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/room/index.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../domain/room/room_fixtures.dart';

List<Override> roomDeviceOverrides({
  Stream<List<ConnectivityResult>>? connectivity,
  LastRoomStore? lastRoom,
}) {
  return [
    connectivityStatusProvider.overrideWith(
      (ref) => connectivity ?? const Stream.empty(),
    ),
    lastRoomStoreProvider.overrideWithValue(lastRoom ?? FakeLastRoomStore()),
  ];
}

final class FakeLastRoomStore implements LastRoomStore {
  FakeLastRoomStore([this.room]);

  String? room;

  @override
  String? read() => room;

  @override
  Future<void> write(String room) async {
    this.room = room;
  }

  @override
  Future<void> clear() async {
    room = null;
  }
}

/// 遵守 [RoomTransport] 的约定：事件异步送达；握手成功前请求以 `notSent` 失败；
/// [check] 只在等待重连时立即连接；连接打开前 [restart] 不做任何事；连接断开时
/// 未完成的读取请求以 `failed` 失败，变更请求以 `unknown` 失败。
final class FakeRoomTransport implements RoomTransport {
  /// [now] 是本地单调时钟，不传时时间静止。
  FakeRoomTransport({
    this.retryIn = const Duration(seconds: 3),
    int Function()? now,
  }) : _clock = ServerClock(now: now ?? () => 1000000);

  final Duration retryIn;
  final _events = StreamController<RoomTransportEvent>.broadcast();
  final ServerClock _clock;
  final List<Map<String, Object?>> requests = [];
  final List<_PendingRequest> _pending = [];
  final List<_PendingRequest> _heldSyncs = [];

  final Map<String, Map<String, Object?>> responses = {};
  Object? requestError;
  Object? syncError;
  Completer<Map<String, Object?>>? requestCompleter;

  /// 与 [requestCompleter] 一样，经它回复的请求在连接断开时失败，无论处理函数
  /// 之后返回什么。
  Future<Map<String, Object?>> Function(String type, Map<String, Object?> data)?
  requestHandler;

  bool holdSyncs = false;

  bool failAttempts = false;

  /// 与真实连接一样，第一次连接打开之前 [start] 不返回。
  Completer<void>? startGate;
  int startCalls = 0;
  int stopCalls = 0;
  int checkCalls = 0;
  int probeCalls = 0;
  int restartCalls = 0;
  int syncCalls = 0;

  /// 包括 [start]、等待重连时的 [check] 和退避计时器发起的连接。
  int connectAttempts = 0;
  RoomSnapshot nextSnapshot = testRoomSnapshot();

  RoomConnectionStatus _status = RoomConnectionStatus.connecting;
  Duration? _retryIn;
  bool _connecting = false;
  bool _ready = false;
  bool _stopped = false;
  Timer? _retryTimer;

  bool get stopped => _stopped;

  @override
  Stream<RoomTransportEvent> get events => _events.stream;

  @override
  ServerClock get clock => _clock;

  @override
  Future<void> start() async {
    startCalls++;
    if (_stopped) return;
    _connect(RoomConnectionStatus.connecting);
    await startGate?.future;
  }

  @override
  Future<Map<String, Object?>> request(String type, Map<String, Object?> data) {
    if (_stopped) {
      return Future.error(
        const RoomRequestException(
          message: '与房间的连接已经停止。',
          outcome: RoomRequestOutcome.notSent,
        ),
      );
    }
    if (!_ready) {
      return Future.error(
        const RoomRequestException(
          message: '还没有连上房间，请连接后重试。',
          outcome: RoomRequestOutcome.notSent,
        ),
      );
    }
    if (type == RoomRequestTypes.roomSync) {
      syncCalls++;
      final error = syncError;
      if (error != null) return Future.error(error);
      if (holdSyncs) {
        final pending = _PendingRequest(type);
        _pending.add(pending);
        _heldSyncs.add(pending);
        return pending.completer.future;
      }
      return Future.value({'room': _snapshotJson(nextSnapshot)});
    }
    requests.add({'type': type, 'data': data});
    final error = requestError;
    if (error != null) return Future.error(error);
    final handler = requestHandler;
    final answer = handler != null
        ? handler(type, data)
        : requestCompleter?.future;
    if (answer == null) {
      return Future.value(responses[type] ?? const <String, Object?>{});
    }
    final pending = _PendingRequest(type);
    _pending.add(pending);
    unawaited(
      answer.then(
        (value) {
          _pending.remove(pending);
          if (!pending.completer.isCompleted) pending.completer.complete(value);
        },
        onError: (Object error) {
          _pending.remove(pending);
          if (!pending.completer.isCompleted) {
            pending.completer.completeError(error);
          }
        },
      ),
    );
    return pending.completer.future;
  }

  void answerSync(RoomSnapshot snapshot) {
    final pending = _heldSyncs.removeAt(0);
    _pending.remove(pending);
    if (!pending.completer.isCompleted) {
      pending.completer.complete({'room': _snapshotJson(snapshot)});
    }
  }

  @override
  void check() {
    checkCalls++;
    if (_stopped || _connecting || _ready || _retryTimer == null) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _connect(RoomConnectionStatus.reconnecting);
  }

  @override
  void probe(Duration deadline) {
    probeCalls++;
    if (!_connecting && !_ready) check();
  }

  @override
  void restart() {
    restartCalls++;
    if (_stopped || !_ready) return;
    disconnect(code: 1012);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (!_stopped) {
      _stopped = true;
      _retryTimer?.cancel();
      _retryTimer = null;
      _detach(leaving: true);
      _setStatus(RoomConnectionStatus.stopped);
    }
    if (!_events.isClosed) await _events.close();
  }

  /// 传入 [serverTimeMs] 时，时钟与真实连接一样从 hello 的临时样本重新估计。
  void emitHello([RoomSnapshot? snapshot, int? serverTimeMs]) {
    if (_stopped) return;
    _connecting = false;
    _ready = true;
    if (serverTimeMs != null) {
      final now = _clock.now();
      _clock
        ..reset()
        ..addProvisionalSample(now, now, serverTimeMs);
    }
    _setStatus(RoomConnectionStatus.open);
    final room = snapshot ?? testRoomSnapshot();
    _emit(RoomHelloReceived(RoomHello(member: testMember, room: room)));
  }

  void disconnect({int code = 1006}) {
    if (_stopped || (!_connecting && !_ready)) return;
    _detach(leaving: false);
    if (shouldStopReconnecting(code)) {
      _stopped = true;
      _setStatus(RoomConnectionStatus.stopped);
      _emit(RoomStopped(code));
      return;
    }
    _setStatus(RoomConnectionStatus.reconnecting, retryIn: retryIn);
    _retryTimer = Timer(retryIn, () {
      _retryTimer = null;
      _connect(RoomConnectionStatus.reconnecting);
    });
  }

  void emit(RoomTransportEvent event) => _emit(event);

  void _connect(RoomConnectionStatus status) {
    final attempt = ++connectAttempts;
    _connecting = true;
    _setStatus(status);
    if (failAttempts) {
      scheduleMicrotask(() {
        if (attempt == connectAttempts && _connecting) disconnect();
      });
    }
  }

  void _detach({required bool leaving}) {
    _connecting = false;
    _ready = false;
    final pending = _pending.toList(growable: false);
    _pending.clear();
    _heldSyncs.clear();
    for (final request in pending) {
      if (request.completer.isCompleted) continue;
      final read = isReadRequest(request.type);
      request.completer.completeError(
        RoomRequestException(
          message: leaving ? '已离开房间。' : '与房间的连接断开。',
          outcome: read
              ? RoomRequestOutcome.failed
              : RoomRequestOutcome.unknown,
        ),
      );
    }
  }

  void _setStatus(RoomConnectionStatus status, {Duration? retryIn}) {
    if (_status == status && _retryIn == retryIn) return;
    _status = status;
    _retryIn = retryIn;
    _emit(RoomConnectionChanged(status, retryIn: retryIn));
  }

  void _emit(RoomTransportEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

final class _PendingRequest {
  _PendingRequest(this.type);

  final String type;
  final completer = Completer<Map<String, Object?>>();
}

final class FakeRoomTransportFactory {
  FakeRoomTransportFactory({this.now});

  final int Function()? now;
  final List<FakeRoomTransport> transports = [];
  final List<String> roomIds = [];
  final List<String> tickets = [];
  Completer<void>? startGate;

  final List<String> servers = [];

  RoomTransport call(String roomId, String ticket) {
    roomIds.add(roomId);
    tickets.add(ticket);
    final transport = FakeRoomTransport(now: now)..startGate = startGate;
    transports.add(transport);
    return transport;
  }

  RoomTransportFactory onServer(String serverId) {
    return (roomId, ticket) {
      servers.add(serverId);
      return call(roomId, ticket);
    };
  }

  FakeRoomTransport get last => transports.last;
}

// 领域枚举名与协议取值相同，因此快照可直接写回 `room.sync` 的回复格式。
Map<String, Object?> _snapshotJson(RoomSnapshot snapshot) {
  final nowPlaying = snapshot.nowPlaying;
  final pending = snapshot.pending;
  return {
    'term': snapshot.term,
    'seq': snapshot.seq,
    'room': {
      'id': snapshot.room.id,
      'name': snapshot.room.name,
      'description': snapshot.room.description,
      'kind': snapshot.room.kind.name,
    },
    'playMode': snapshot.playMode.name,
    'nowPlaying': nowPlaying == null
        ? null
        : {
            'entry': _entryJson(nowPlaying.entry),
            'mediaUrl': nowPlaying.mediaUrl,
            'startedAtMs': nowPlaying.startedAtMs,
            'durationMs': nowPlaying.durationMs,
            'gain': nowPlaying.gain,
            'lyric': nowPlaying.lyric,
          },
    'pending': pending == null ? null : _entryJson(pending),
    'items': snapshot.items.map(_entryJson).toList(),
    'members': {
      'sessions': snapshot.members.map(_memberJson).toList(),
      'onlineCount': snapshot.onlineCount,
    },
  };
}

Map<String, Object?> _entryJson(QueueEntry entry) {
  final by = entry.requestedBy;
  return {
    'id': entry.id,
    'track': {'source': entry.track.source.name, 'id': entry.track.id},
    'meta': {
      'title': entry.meta.title,
      'artist': entry.meta.artist,
      'album': entry.meta.album,
      'coverUrl': entry.meta.coverUrl,
      'pageUrl': entry.meta.pageUrl,
      'durationMs': entry.meta.durationMs,
    },
    'by': by == null ? null : _memberJson(by),
    'auto': entry.auto,
    'likes': entry.likes,
    'status': entry.status.name,
  };
}

Map<String, Object?> _memberJson(Member member) {
  return {
    'id': member.id,
    'name': member.name,
    'avatarHash': member.avatarHash,
  };
}
