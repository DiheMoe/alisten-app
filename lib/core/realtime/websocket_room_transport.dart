import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/clock/server_clock.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/protocol/domain_mapper.dart';
import 'package:alisten/core/protocol/protocol.gen.dart' as protocol;
import 'package:alisten/core/realtime/reconnect_policy.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

const _helloType = 'hello';
const _pingType = 'ping';
const _errorEventType = 'error';

const _abnormalClosure = 1006;

const _helloIncompatible = RoomRequestException(
  code: LocalErrorCodes.protocolMismatch,
  message: '客户端与服务器的协议不兼容，请升级 Alisten。',
  outcome: RoomRequestOutcome.failed,
);

const _logSource = 'room';

final class WebSocketRoomTransport implements RoomTransport {
  factory WebSocketRoomTransport({
    required Uri baseUri,
    required String roomId,
    required String ticket,
    WebSocketChannelFactory? channelFactory,
    ServerClock? clock,
    Random? random,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration requestTimeout = const Duration(seconds: 60),
    Duration pingInterval = const Duration(seconds: 5),
    Duration idleTimeout = const Duration(seconds: 25),
  }) {
    return WebSocketRoomTransport._(
      baseUri,
      roomId,
      ticket,
      channelFactory ?? WebSocketChannel.connect,
      clock ?? ServerClock(),
      random ?? Random(),
      connectTimeout,
      requestTimeout,
      pingInterval,
      idleTimeout,
    );
  }

  WebSocketRoomTransport._(
    this._baseUri,
    this._roomId,
    this._ticket,
    this._channelFactory,
    this._clock,
    this._random,
    this._connectTimeout,
    this._requestTimeout,
    this._pingInterval,
    this._idleTimeout,
  );

  final Uri _baseUri;
  final String _roomId;
  final String _ticket;
  final WebSocketChannelFactory _channelFactory;
  final ServerClock _clock;
  final Random _random;
  final Duration _connectTimeout;
  final Duration _requestTimeout;
  final Duration _pingInterval;
  final Duration _idleTimeout;
  final _events = StreamController<RoomTransportEvent>.broadcast();
  final Map<String, _PendingRequest> _pending = {};

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Timer? _pingTimer;
  Timer? _idleTimer;
  Timer? _probeTimer;
  RoomConnectionStatus _status = RoomConnectionStatus.connecting;
  Duration? _retryIn;
  bool _ready = false;
  bool _stopped = false;
  int _attempt = 0;
  int _nextId = 0;

  @override
  Stream<RoomTransportEvent> get events => _events.stream;

  @override
  ServerClock get clock => _clock;

  @override
  Future<void> start() async {
    if (_stopped) return;
    _setStatus(RoomConnectionStatus.connecting);
    await _open();
  }

  Future<void> _open() async {
    if (_stopped || _channel != null) return;
    final channel = _channelFactory(
      _baseUri.replace(
        scheme: _baseUri.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws',
      ),
    );
    _channel = channel;
    try {
      await channel.ready.timeout(_connectTimeout);
    } on Object {
      _lost(channel, _abnormalClosure);
      return;
    }
    if (!identical(_channel, channel) || _stopped) return;
    _subscription = channel.stream.listen(
      (message) => _receive(channel, message),
      onError: (Object _) => _lost(channel, _abnormalClosure),
      onDone: () => _lost(channel, channel.closeCode ?? _abnormalClosure),
      cancelOnError: true,
    );
    _restartIdle(channel);
    unawaited(_handshake(channel));
  }

  Future<void> _handshake(WebSocketChannel channel) async {
    final sentAt = _clock.now();
    final Map<String, Object?> data;
    try {
      data = await _send(
        channel,
        _helloType,
        protocol.HelloRequest(
          roomId: _roomId,
          ticket: _ticket,
          protocolVersion: protocol.protocolVersion,
        ).toJson(),
        timeout: _connectTimeout,
      );
    } on RoomRequestException catch (error) {
      if (!identical(_channel, channel) || _stopped) return;
      final code = error.code;
      if (code != null) {
        _emit(RoomErrorReceived(code: code, message: error.message));
      }
      _lost(channel, _helloCloseCode(code));
      return;
    }
    if (!identical(_channel, channel) || _stopped) return;
    final receivedAt = _clock.now();
    final int serverTimeMs;
    final RoomHello hello;
    try {
      final response = protocol.HelloResponse.fromJson(data);
      serverTimeMs = response.serverTimeMs;
      hello = RoomHello(
        member: toDomainMember(response.member),
        room: toDomainSnapshot(response.room),
      );
    } on FormatException {
      AppLog.warn(_logSource, 'hello response not understood');
      _emit(
        RoomErrorReceived(
          code: LocalErrorCodes.protocolMismatch,
          message: _helloIncompatible.message,
        ),
      );
      _lost(channel, protocol.WsCloseCodes.clientOutdated);
      return;
    }
    _ready = true;
    _attempt = 0;
    _clock
      ..reset()
      ..addProvisionalSample(sentAt, receivedAt, serverTimeMs);
    _setStatus(RoomConnectionStatus.open);
    _emit(RoomHelloReceived(hello));
    _sendPing(channel);
    _pingTimer = Timer.periodic(_pingInterval, (_) => _sendPing(channel));
  }

  @override
  Future<Map<String, Object?>> request(String type, Map<String, Object?> data) {
    final channel = _channel;
    if (_stopped) {
      return Future.error(
        const RoomRequestException(
          message: '与房间的连接已经停止。',
          outcome: RoomRequestOutcome.notSent,
        ),
      );
    }
    if (!_ready || channel == null) {
      return Future.error(
        const RoomRequestException(
          message: '还没有连上房间，请连接后重试。',
          outcome: RoomRequestOutcome.notSent,
        ),
      );
    }
    return _send(channel, type, data, timeout: _requestTimeout);
  }

  Future<Map<String, Object?>> _send(
    WebSocketChannel channel,
    String type,
    Map<String, Object?> data, {
    required Duration timeout,
  }) {
    if (!identical(_channel, channel) || _stopped) {
      return Future.error(
        const RoomRequestException(
          message: '与房间的连接已断开。',
          outcome: RoomRequestOutcome.notSent,
        ),
      );
    }
    final id = '${++_nextId}';
    final String frame;
    try {
      frame = jsonEncode(
        protocol.WsRequest(id: id, type: type, data: data).toJson(),
      );
    } on JsonUnsupportedObjectError {
      AppLog.warn(_logSource, 'request could not be encoded', type: type);
      return Future.error(
        const RoomRequestException(
          message: '请求内容无法发送。',
          outcome: RoomRequestOutcome.notSent,
        ),
      );
    }
    final pending = _PendingRequest(type);
    pending.timer = Timer(timeout, () {
      if (_pending.remove(id) == null) return;
      _fail(
        pending,
        isReadRequest(type)
            ? const RoomRequestException(
                message: '服务器没有及时响应，请稍后重试。',
                outcome: RoomRequestOutcome.failed,
              )
            : const RoomRequestException(
                message: '服务器没有及时响应，操作结果未知，请同步后确认。',
                outcome: RoomRequestOutcome.unknown,
              ),
      );
    });
    _pending[id] = pending;
    try {
      channel.sink.add(frame);
    } on Object {
      _pending.remove(id);
      pending.timer.cancel();
      _fail(
        pending,
        const RoomRequestException(
          message: '请求发送失败。',
          outcome: RoomRequestOutcome.notSent,
        ),
      );
      _lost(channel, _abnormalClosure);
    }
    return pending.completer.future;
  }

  void _receive(WebSocketChannel channel, Object? message) {
    if (!identical(_channel, channel)) return;
    _restartIdle(channel);
    _probeTimer?.cancel();
    _probeTimer = null;
    final Object? frame;
    try {
      frame = message is String ? jsonDecode(message) : null;
    } on FormatException {
      AppLog.debug(_logSource, 'frame is not JSON');
      return;
    }
    if (frame is! Map<String, Object?>) {
      AppLog.debug(_logSource, 'frame is not a JSON object');
      return;
    }
    switch (frame['kind']) {
      case 'response':
        _receiveResponse(frame);
      case 'event':
        _receiveEvent(frame);
      default:
        AppLog.debug(_logSource, 'frame kind not understood');
    }
  }

  void _receiveResponse(Map<String, Object?> frame) {
    final id = frame['id'];
    if (id is! String) {
      AppLog.debug(_logSource, 'response without id');
      return;
    }
    final pending = _pending.remove(id);
    if (pending == null) return;
    pending.timer.cancel();
    final protocol.WsResponse response;
    final protocol.ErrorInfo? error;
    try {
      response = protocol.WsResponse.fromJson(frame);
      final errorJson = response.error;
      error = errorJson == null ? null : protocol.ErrorInfo.fromJson(errorJson);
    } on FormatException {
      _fail(
        pending,
        pending.type == _helloType
            ? _helloIncompatible
            : RoomRequestException.undecodable(pending.type),
      );
      return;
    }
    if (error == null) {
      pending.completer.complete(response.data);
      return;
    }
    _fail(
      pending,
      RoomRequestException(
        code: error.code.wireValue,
        message: error.message,
        outcome: _errorOutcome(pending.type, error.code),
      ),
    );
  }

  void _receiveEvent(Map<String, Object?> frame) {
    final protocol.WsEvent event;
    try {
      event = protocol.WsEvent.fromJson(frame);
    } on FormatException {
      AppLog.debug(_logSource, 'event envelope not understood');
      return;
    }
    if (event.type == _errorEventType) {
      try {
        final error = protocol.ErrorInfo.fromJson(event.data);
        _emit(
          RoomErrorReceived(code: error.code.wireValue, message: error.message),
        );
      } on FormatException {
        AppLog.debug(_logSource, 'error event not understood');
      }
      return;
    }
    final term = event.term;
    final seq = event.seq;
    if (!_ready || term == null || seq == null) return;
    RoomEvent roomEvent;
    try {
      roomEvent = toDomainEvent(event.type, term, seq, event.data);
    } on FormatException {
      AppLog.debug(_logSource, 'room event not understood', type: event.type);
      roomEvent = UnreadableRoomEvent(term: term, seq: seq);
    }
    _emit(RoomEventReceived(roomEvent));
  }

  void _sendPing(WebSocketChannel channel) {
    if (!_ready || !identical(_channel, channel) || _stopped) return;
    final sentAt = _clock.now();
    final generation = _clock.generation;
    unawaited(
      _send(
            channel,
            _pingType,
            protocol.PingRequest(clientTimeMs: sentAt).toJson(),
            timeout: _requestTimeout,
          )
          .then((data) {
            final response = protocol.PingResponse.fromJson(data);
            _clock.addSample(
              sentAt,
              _clock.now(),
              response.serverTimeMs,
              generation: generation,
            );
          })
          .catchError((Object _) {}),
    );
  }

  @override
  void check() {
    if (_stopped || _channel != null || _retryTimer == null) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _setStatus(RoomConnectionStatus.reconnecting);
    unawaited(_open());
  }

  @override
  void probe(Duration deadline) {
    final channel = _channel;
    if (channel == null) {
      check();
      return;
    }
    if (_stopped || !_ready || _probeTimer != null) return;
    _probeTimer = Timer(deadline, () {
      _probeTimer = null;
      AppLog.debug(_logSource, 'probe unanswered', delay: deadline);
      _lost(channel, _abnormalClosure);
    });
    _sendPing(channel);
  }

  @override
  void restart() {
    final channel = _channel;
    if (_stopped || channel == null || !_ready) return;
    _lost(channel, protocol.WsCloseCodes.serviceRestart);
  }

  void _restartIdle(WebSocketChannel channel) {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () {
      AppLog.debug(_logSource, 'idle timeout');
      _lost(channel, _abnormalClosure);
    });
  }

  void _lost(WebSocketChannel channel, int code) {
    if (!identical(_channel, channel)) return;
    _detach(channel);
    if (_stopped) return;
    if (shouldStopReconnecting(code)) {
      _stopped = true;
      AppLog.info(_logSource, 'connection stopped', closeCode: code);
      _setStatus(RoomConnectionStatus.stopped);
      _emit(RoomStopped(code));
      return;
    }
    _attempt++;
    final delay = reconnectDelay(_attempt, _random);
    AppLog.debug(
      _logSource,
      'connection lost',
      closeCode: code,
      attempt: _attempt,
      delay: delay,
    );
    _setStatus(RoomConnectionStatus.reconnecting, retryIn: delay);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _setStatus(RoomConnectionStatus.reconnecting);
      unawaited(_open());
    });
  }

  void _detach(WebSocketChannel channel, {bool leaving = false}) {
    _channel = null;
    _ready = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _probeTimer?.cancel();
    _probeTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final request in pending) {
      request.timer.cancel();
      // 等待中的请求都已写入连接。
      _fail(request, switch ((leaving, isReadRequest(request.type))) {
        (true, true) => const RoomRequestException(
          message: '已离开房间。',
          outcome: RoomRequestOutcome.failed,
        ),
        (true, false) => const RoomRequestException(
          message: '已离开房间，已发出的操作结果未知。',
          outcome: RoomRequestOutcome.unknown,
        ),
        (false, true) => const RoomRequestException(
          message: '与房间的连接断开，请稍后重试。',
          outcome: RoomRequestOutcome.failed,
        ),
        (false, false) => const RoomRequestException(
          message: '与房间的连接断开，已发出的操作结果未知。',
          outcome: RoomRequestOutcome.unknown,
        ),
      });
    }
    unawaited(channel.sink.close().catchError((Object _) {}));
  }

  @override
  Future<void> stop() async {
    if (!_stopped) {
      _stopped = true;
      _retryTimer?.cancel();
      _retryTimer = null;
      final channel = _channel;
      if (channel != null) _detach(channel, leaving: true);
      _setStatus(RoomConnectionStatus.stopped);
    }
    if (!_events.isClosed) await _events.close();
  }

  void _fail(_PendingRequest pending, RoomRequestException error) {
    if (pending.completer.isCompleted) return;
    AppLog.debug(
      _logSource,
      'request failed',
      type: pending.type,
      code: error.code,
      outcome: error.outcome,
    );
    pending.completer.completeError(error);
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

// 变更请求生效后仍可能收到 UNAVAILABLE 或 INTERNAL（如网关超时），
// 所以只有读取请求把它们算作失败。
RoomRequestOutcome _errorOutcome(String type, protocol.ErrorCode code) {
  if (isReadRequest(type)) return RoomRequestOutcome.failed;
  return switch (code) {
    protocol.ErrorCode.unavailable ||
    protocol.ErrorCode.internal => RoomRequestOutcome.unknown,
    _ => RoomRequestOutcome.failed,
  };
}

// 与服务端拒绝握手之后发送的关闭码一致。
int _helloCloseCode(String? code) {
  if (code == LocalErrorCodes.protocolMismatch) {
    return protocol.WsCloseCodes.clientOutdated;
  }
  final errorCode = protocol.ErrorCode.values
      .where((value) => value.wireValue == code)
      .firstOrNull;
  return switch (errorCode) {
    protocol.ErrorCode.invalidArgument => protocol.WsCloseCodes.invalidArgument,
    protocol.ErrorCode.unauthorized => protocol.WsCloseCodes.unauthorized,
    protocol.ErrorCode.notFound => protocol.WsCloseCodes.notFound,
    protocol.ErrorCode.clientOutdated => protocol.WsCloseCodes.clientOutdated,
    protocol.ErrorCode.internal => protocol.WsCloseCodes.internal,
    protocol.ErrorCode.unavailable => protocol.WsCloseCodes.unavailable,
    _ => _abnormalClosure,
  };
}

final class _PendingRequest {
  _PendingRequest(this.type);

  final String type;
  final completer = Completer<Map<String, Object?>>();
  late final Timer timer;
}
