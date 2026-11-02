import 'dart:convert';

enum OriginProblem { malformed, cleartext }

sealed class OriginInput {
  const OriginInput();
}

final class ValidOrigin extends OriginInput {
  const ValidOrigin(this.origin);

  /// 小写的 scheme 和主机名，省略默认端口，不含路径和末尾的 `/`。
  /// 同一个服务器只有这一种写法，存储键名由它推导。
  final String origin;
}

final class InvalidOrigin extends OriginInput {
  const InvalidOrigin(this.problem);

  final OriginProblem problem;
}

/// 没有 scheme 时按 https 处理；丢弃路径、查询和片段。
OriginInput parseServerOrigin(String input, {required bool allowCleartext}) {
  var text = input.trim();
  if (text.isEmpty) return const InvalidOrigin(OriginProblem.malformed);
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return const InvalidOrigin(OriginProblem.malformed);
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' && !allowCleartext) {
    return const InvalidOrigin(OriginProblem.cleartext);
  }
  if (scheme != 'https' && scheme != 'http') {
    return const InvalidOrigin(OriginProblem.malformed);
  }
  // 末尾带点的完整域名与不带点的是同一个主机，统一去掉末尾的点。
  var host = uri.host.toLowerCase();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  final int? port;
  try {
    port = uri.hasPort ? uri.port : null;
  } on FormatException {
    // Uri 接受任意长的端口数字，超出 int 范围时读取 `port` 才抛出。
    return const InvalidOrigin(OriginProblem.malformed);
  }
  // Uri 会把非 ASCII 字符和空格转义成 `%XX` 后接受，也接受主机名中的空标签，
  // 这样的主机名都无法连接。
  if (host.isEmpty ||
      host.startsWith('.') ||
      host.endsWith('.') ||
      host.contains('..') ||
      host.contains('%') ||
      (port != null && (port < 1 || port > 65535))) {
    return const InvalidOrigin(OriginProblem.malformed);
  }
  final defaultPort = scheme == 'https' ? 443 : 80;
  final suffix = port != null && port != defaultPort ? ':$port' : '';
  return ValidOrigin(
    '$scheme://${host.contains(':') ? '[$host]' : host}$suffix',
  );
}

/// 64 位 FNV-1a 哈希，16 位小写十六进制。它出现在已落盘的存储键名中，
/// 算法和输入的写法都不能再改。
String serverIdFor(String origin) {
  // 偏移基数 0xcbf29ce484222325 超出 int 的正数范围，写成补码；原生 int 乘法按
  // 2^64 回绕。
  var hash = -0x340d631b7bdddcdb;
  for (final byte in utf8.encode(origin)) {
    hash ^= byte;
    hash *= 0x100000001b3;
  }
  return (hash >>> 32).toRadixString(16).padLeft(8, '0') +
      (hash & 0xffffffff).toRadixString(16).padLeft(8, '0');
}

String originAuthority(String origin) =>
    origin.substring(origin.indexOf('://') + 3);
