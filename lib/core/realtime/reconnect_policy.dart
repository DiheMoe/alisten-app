import 'dart:math';

import 'package:alisten/core/protocol/protocol.gen.dart' show WsCloseCodes;

/// 延迟随机浮动 ±20%，避免服务端重启时一起断开的客户端同时重连。
Duration reconnectDelay(int attempt, Random random) {
  if (attempt < 1) throw ArgumentError.value(attempt, 'attempt');
  final baseMs = attempt >= 5 ? 30000 : 3000 << (attempt - 1);
  final factor = 0.8 + 0.4 * random.nextDouble();
  return Duration(milliseconds: (baseMs * factor).round());
}

bool shouldStopReconnecting(int code) {
  return const {
    WsCloseCodes.invalidArgument,
    WsCloseCodes.unauthorized,
    WsCloseCodes.notFound,
    WsCloseCodes.clientOutdated,
  }.contains(code);
}
