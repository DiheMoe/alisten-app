import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/protocol/http.gen.dart' as http;
import 'package:alisten/core/protocol/protocol.gen.dart' as protocol;
import 'package:alisten/core/realtime/websocket_room_transport.dart';
import 'package:alisten/features/server/application/server_probe.dart';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/web_socket_channel.dart';

const _logSource = 'server';

final class AlistenServerProbe implements ServerProbe {
  AlistenServerProbe({
    required this._dio,
    WebSocketChannelFactory? connect,
    this._siteTimeout = const Duration(seconds: 10),
    this._connectTimeout = const Duration(seconds: 10),
    this._handshakeTimeout = const Duration(seconds: 15),
  }) : _connect = connect ?? WebSocketChannel.connect;

  // 服务端先比对协议版本，再用房间 id 和票据进房。这个房间不存在，版本一致时
  // 握手以 NOT_FOUND 结束，不会进入房间。
  static const probeRoomId = '00000000-0000-4000-8000-000000000000';
  static const probeTicket = 'probe';
  static const probeRequestId = 'probe';

  static const maxSiteBodyBytes = 64 * 1024;

  // 服务端限制品牌名不超过 20 个字符；这里放宽，只拦截明显不是品牌名的值。
  static const maxBrandNameRunes = 64;

  final Dio _dio;
  final WebSocketChannelFactory _connect;
  final Duration _siteTimeout;
  final Duration _connectTimeout;
  final Duration _handshakeTimeout;

  @override
  Future<ProbeResult> probe(String origin) async {
    final site = await probeSite(origin);
    if (site is ProbeFailed) return site;
    final failure = await probeHandshake(origin);
    return failure == null ? site : ProbeFailed(failure);
  }

  @override
  Future<String?> fetchBrandName(String origin) async {
    return switch (await probeSite(origin)) {
      ProbeSucceeded(:final brandName) => brandName,
      ProbeFailed() => null,
    };
  }

  @override
  Future<ProbeResult> probeSite(
    String origin, {
    Duration? timeout,
    Future<void>? cancel,
  }) async {
    final result = await _readSite(origin, timeout ?? _siteTimeout, cancel);
    if (result case ProbeFailed(:final failure)) {
      AppLog.debug(_logSource, 'site probe failed', outcome: failure);
    }
    return result;
  }

  Future<ProbeResult> _readSite(
    String origin,
    Duration timeout,
    Future<void>? cancel,
  ) async {
    final cancelToken = CancelToken();
    unawaited(cancel?.then((_) => cancelToken.cancel()));
    final ({int status, String? body}) site;
    try {
      site = await _fetchSite(origin, cancelToken).timeout(
        timeout,
        onTimeout: () {
          cancelToken.cancel();
          throw TimeoutException(null, timeout);
        },
      );
    } on Object {
      return const ProbeFailed(ProbeFailure.unreachable);
    }
    final body = site.body;
    if (site.status == 200) {
      final brandName = body == null ? null : _brandName(body);
      return brandName == null
          ? const ProbeFailed(ProbeFailure.notAlisten)
          : ProbeSucceeded(origin: origin, brandName: brandName);
    }
    // 5xx 多半是网关后的 Alisten 暂时不可用（502/503 网关页、500 空体）。其他
    // 状态只有协议错误格式的回复来自 Alisten，其余（含重定向）来自别的站点。
    if (site.status >= 500 || (body != null && _isProtocolError(body))) {
      return const ProbeFailed(ProbeFailure.unreachable);
    }
    return const ProbeFailed(ProbeFailure.notAlisten);
  }

  // 响应体超过上限或不是 UTF-8 时 body 为 null。
  Future<({int status, String? body})> _fetchSite(
    String origin,
    CancelToken cancelToken,
  ) async {
    final response = await _dio.get<ResponseBody>(
      '$origin${http.RestEndpoints.getSite.path}',
      cancelToken: cancelToken,
      options: Options(
        followRedirects: false,
        validateStatus: (_) => true,
        responseType: ResponseType.stream,
      ),
    );
    final status = response.statusCode ?? 0;
    final stream = response.data?.stream;
    if (stream == null) return (status: status, body: '');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      bytes.add(chunk);
      if (bytes.length > AlistenServerProbe.maxSiteBodyBytes) {
        // 取消订阅 Dio 包装的响应流不会关闭连接，只有 cancelToken 会。
        cancelToken.cancel();
        return (status: status, body: null);
      }
    }
    try {
      return (status: status, body: utf8.decode(bytes.takeBytes()));
    } on FormatException {
      return (status: status, body: null);
    }
  }

  @override
  Future<ProbeFailure?> probeHandshake(
    String origin, {
    Future<void>? cancel,
  }) async {
    final (:verdict, :closeCode, :code) = await _handshake(origin, cancel);
    final failure = verdict.failure;
    if (failure != null) {
      AppLog.debug(
        _logSource,
        'handshake probe failed',
        outcome: failure,
        closeCode: closeCode,
        code: code,
      );
    }
    return failure;
  }

  Future<_Handshake> _handshake(String origin, Future<void>? cancel) async {
    final WebSocketChannel channel;
    try {
      final base = Uri.parse(origin);
      channel = _connect(
        base.replace(
          scheme: base.scheme == 'https' ? 'wss' : 'ws',
          path: '/ws',
        ),
      );
    } on Object {
      return (verdict: _Verdict.unverified, closeCode: null, code: null);
    }
    final outcome = Completer<_Handshake>();
    void decide(_Verdict verdict, {int? closeCode, String? code}) {
      if (outcome.isCompleted) return;
      outcome.complete((verdict: verdict, closeCode: closeCode, code: code));
    }

    StreamSubscription<dynamic>? subscription;
    void sendHello() {
      if (outcome.isCompleted) return;
      subscription = channel.stream.listen(
        (message) {
          if (_reply(message) case (:final verdict, :final code)) {
            decide(verdict, code: code);
          }
        },
        onError: (Object _) => decide(_Verdict.unverified),
        onDone: () {
          final closeCode = channel.closeCode;
          decide(_closeVerdict(closeCode), closeCode: closeCode);
        },
        cancelOnError: true,
      );
      channel.sink.add(_helloFrame);
    }

    final deadline = Timer(
      _handshakeTimeout,
      () => decide(_Verdict.unverified),
    );
    unawaited(cancel?.then((_) => decide(_Verdict.unverified)));
    unawaited(
      channel.ready
          .timeout(_connectTimeout)
          .then((_) => sendHello())
          .catchError((Object _) => decide(_Verdict.unverified)),
    );
    final result = await outcome.future;
    deadline.cancel();
    unawaited(subscription?.cancel());
    unawaited(
      channel.sink.close(status.normalClosure).catchError((Object _) {}),
    );
    return result;
  }
}

typedef _Handshake = ({_Verdict verdict, int? closeCode, String? code});

final _helloFrame = jsonEncode(
  protocol.WsRequest(
    id: AlistenServerProbe.probeRequestId,
    type: 'hello',
    data: const protocol.HelloRequest(
      roomId: AlistenServerProbe.probeRoomId,
      ticket: AlistenServerProbe.probeTicket,
      protocolVersion: protocol.protocolVersion,
    ).toJson(),
  ).toJson(),
);

enum _Verdict {
  compatible(null),
  incompatible(ProbeFailure.incompatible),
  unverified(ProbeFailure.unverified);

  const _Verdict(this.failure);

  final ProbeFailure? failure;
}

({_Verdict verdict, String? code})? _reply(Object? message) {
  final Object? frame;
  try {
    frame = message is String ? jsonDecode(message) : null;
  } on FormatException {
    return null;
  }
  if (frame is! Map<String, Object?> ||
      frame['kind'] != 'response' ||
      frame['id'] != AlistenServerProbe.probeRequestId) {
    return null;
  }
  try {
    final error = protocol.WsResponse.fromJson(frame).error;
    if (error == null) return (verdict: _Verdict.unverified, code: null);
    final code = protocol.ErrorInfo.fromJson(error).code;
    final verdict = switch (code) {
      protocol.ErrorCode.clientOutdated => _Verdict.incompatible,
      protocol.ErrorCode.notFound ||
      protocol.ErrorCode.unauthorized => _Verdict.compatible,
      _ => _Verdict.unverified,
    };
    return (verdict: verdict, code: code.wireValue);
  } on FormatException {
    return (verdict: _Verdict.unverified, code: null);
  }
}

_Verdict _closeVerdict(int? code) {
  return switch (code) {
    protocol.WsCloseCodes.clientOutdated => _Verdict.incompatible,
    protocol.WsCloseCodes.notFound ||
    protocol.WsCloseCodes.unauthorized => _Verdict.compatible,
    _ => _Verdict.unverified,
  };
}

// 只认品牌名：其余字段随服务端版本增减，旧版本的服务器同样要能认出来，再由
// 握手判断是否兼容。
String? _brandName(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  final raw = json['brandName'];
  if (raw is! String) return null;
  final name = raw.trim();
  if (name.isEmpty ||
      name.runes.length > AlistenServerProbe.maxBrandNameRunes ||
      name.runes.any(_isControl)) {
    return null;
  }
  return name;
}

// Unicode 的 Cc 类。
bool _isControl(int rune) => rune < 0x20 || (rune >= 0x7f && rune <= 0x9f);

bool _isProtocolError(String body) {
  try {
    final json = jsonDecode(body);
    final error = json is Map<String, Object?> ? json['error'] : null;
    if (error is! Map<String, Object?>) return false;
    protocol.ErrorInfo.fromJson(error);
    return true;
  } on protocol.ProtocolMismatchException {
    // 较新的服务端可能返回本客户端不认识的错误码。
    return true;
  } on FormatException {
    return false;
  }
}
