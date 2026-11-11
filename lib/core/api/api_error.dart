const _rateLimited = 'RATE_LIMITED';

/// 客户端本地产生的错误码；其余错误码都取自协议的 `ErrorCode`。
abstract final class LocalErrorCodes {
  /// 没有 memberToken，请求未发出。
  static const noToken = 'LOCAL_NO_TOKEN';

  /// 没有收到 Alisten 接口的回复：连接失败、超时，
  /// 或代理返回了非协议格式的错误页。
  static const network = 'NETWORK';

  /// 回复无法被当前版本的客户端解码。
  static const protocolMismatch = 'PROTOCOL_MISMATCH';
}

final class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    required this.status,
    this.retryAfter,
  });

  const ApiException.protocolMismatch(this.status)
    : code = LocalErrorCodes.protocolMismatch,
      message = '服务器返回了无法识别的数据，请升级 Alisten。',
      retryAfter = null;

  final String code;

  final String message;
  final int? status;

  final Duration? retryAfter;

  /// 请求被限流且未执行。
  bool get rateLimited => code == _rateLimited;

  /// 没有拿到可用的答复：连接失败，或 2xx 回复无法解码。变更请求遇到它时服务端
  /// 可能已经应用了修改，结果按未知处理。
  bool get answerLost {
    final status = this.status;
    return code == LocalErrorCodes.network ||
        (code == LocalErrorCodes.protocolMismatch &&
            status != null &&
            status >= 200 &&
            status < 300);
  }

  @override
  String toString() => 'ApiException($code, $status)';
}

String rateLimitedText(ApiException error) {
  final seconds = error.retryAfter?.inSeconds;
  return seconds == null || seconds <= 0
      ? error.message
      : '请求太频繁，请 $seconds 秒后再试';
}
