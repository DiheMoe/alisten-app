import 'dart:convert';

/// 服务端发来了客户端生成时没有的值，例如新版协议新增的枚举值。
final class ProtocolMismatchException implements FormatException {
  const ProtocolMismatchException(this.message);

  @override
  final String message;

  @override
  Object? get source => null;

  @override
  int? get offset => null;

  @override
  String toString() => 'ProtocolMismatchException: $message';
}

// 生成的 `fromJson` 只解码服务端发来的数据，因此只检查字段是否存在、
// 是否为 null 以及 JSON 类型。未知字段和请求侧的取值约束（长度、格式、范围、
// 链接）交给服务端，新版服务端扩展协议时才不会让客户端出错。

Object? requiredField(Map<String, Object?> json, String key, String owner) {
  if (!json.containsKey(key)) {
    throw FormatException('$owner.$key is missing');
  }
  return json[key];
}

Object? optionalField(Map<String, Object?> json, String key, String owner) {
  final value = json[key];
  if (value == null && json.containsKey(key)) {
    throw FormatException('$owner.$key must not be null');
  }
  return value;
}

Map<String, Object?> readObject(Object? value, String path) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('$path must be an object');
}

List<Object?> readList(Object? value, String path) {
  if (value is List<Object?>) return value;
  throw FormatException('$path must be an array');
}

String readString(Object? value, String path) {
  if (value is String) return value;
  throw FormatException('$path must be a string');
}

int readInt(Object? value, String path) {
  if (value is int) return value;
  throw FormatException('$path must be an integer');
}

double readNumber(Object? value, String path) {
  if (value is num) return value.toDouble();
  throw FormatException('$path must be a number');
}

bool readBool(Object? value, String path) {
  if (value is bool) return value;
  throw FormatException('$path must be a boolean');
}

T readEnum<T>(
  Object? value,
  List<T> values,
  String Function(T value) wireValue,
  String name,
) {
  final wire = readString(value, name);
  for (final candidate in values) {
    if (wireValue(candidate) == wire) return candidate;
  }
  throw ProtocolMismatchException('$name has no value "$wire"');
}

final class WsRequest {
  const WsRequest({required this.id, required this.type, required this.data});

  final String id;
  final String type;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'request',
    'id': id,
    'type': type,
    'data': data,
  };
}

final class WsResponse {
  const WsResponse({
    required this.id,
    required this.type,
    required this.data,
    this.error,
  });

  factory WsResponse.fromJson(Map<String, Object?> json) {
    _checkKind(json, 'response', 'WsResponse');
    return WsResponse(
      id: readString(requiredField(json, 'id', 'WsResponse'), 'WsResponse.id'),
      type: readString(
        requiredField(json, 'type', 'WsResponse'),
        'WsResponse.type',
      ),
      data: readObject(
        requiredField(json, 'data', 'WsResponse'),
        'WsResponse.data',
      ),
      error: switch (optionalField(json, 'error', 'WsResponse')) {
        null => null,
        final value => readObject(value, 'WsResponse.error'),
      },
    );
  }

  final String id;
  final String type;
  final Map<String, Object?> data;

  /// 失败请求的 `ErrorInfo`，此处不解码：传输层要先把回复对应到等待中的请求，
  /// 即使错误本身无法解码，也能让该请求失败。
  final Map<String, Object?>? error;
}

final class WsEvent {
  const WsEvent({required this.type, required this.data, this.term, this.seq});

  factory WsEvent.fromJson(Map<String, Object?> json) {
    _checkKind(json, 'event', 'WsEvent');
    final term = switch (optionalField(json, 'term', 'WsEvent')) {
      null => null,
      final value => readInt(value, 'WsEvent.term'),
    };
    final seq = switch (optionalField(json, 'seq', 'WsEvent')) {
      null => null,
      final value => readInt(value, 'WsEvent.seq'),
    };
    if ((term == null) != (seq == null)) {
      throw const FormatException('WsEvent term and seq must come together');
    }
    return WsEvent(
      type: readString(requiredField(json, 'type', 'WsEvent'), 'WsEvent.type'),
      data: readObject(requiredField(json, 'data', 'WsEvent'), 'WsEvent.data'),
      term: term,
      seq: seq,
    );
  }

  final String type;
  final Map<String, Object?> data;

  // 只有房间事件带这两个字段；`error` 等连接事件不属于房间的事件序列。
  final int? term;
  final int? seq;
}

void _checkKind(Map<String, Object?> json, String kind, String owner) {
  if (requiredField(json, 'kind', owner) != kind) {
    throw FormatException('$owner.kind must be $kind');
  }
}

enum HttpAuth { none, member, ticket, admin }

final class RestEndpoint {
  const RestEndpoint({
    required this.name,
    required this.method,
    required this.path,
    required this.auth,
    required this.successStatus,
    required this.hasLocation,
    required this.pathParameters,
  });

  final String name;
  final String method;
  final String path;
  final HttpAuth auth;
  final int successStatus;
  final bool hasLocation;
  final List<String> pathParameters;

  String buildPath(Map<String, String> parameters) {
    final expected = pathParameters.toSet();
    final actual = parameters.keys.toSet();
    if (expected.length != actual.length || !expected.containsAll(actual)) {
      throw ArgumentError(
        'Path parameters must be exactly ${pathParameters.join(', ')}',
      );
    }
    return path.replaceAllMapped(
      _pathParameter,
      (match) => Uri.encodeComponent(parameters[match.group(1)!]!),
    );
  }
}

final _pathParameter = RegExp(r'\{([^}]+)\}');

// 链接规则与后端的 x-url 校验（protocol/decode.go 的 validURL）一致，并用后端的
// protocol/testdata/Link.json 验证。

bool isValidLink(String value) => _parseLink(value) != null;

/// 只把 scheme 和 authority 中的 ASCII 字母转为小写，与后端由链接生成曲目 ID 的
/// 规则一致；其余字节都有意义，保持不变。
String normalizeLink(String value) {
  final parts = _parseLink(value);
  if (parts == null) {
    throw const FormatException('Invalid HTTP(S) link');
  }
  return '${_asciiLower(parts.scheme)}://${_asciiLower(parts.authority)}'
      '${parts.remainder}';
}

final _decimal = RegExp(r'^[0-9]+$');
final _ipv4Octet = RegExp(r'^(?:0|[1-9][0-9]{0,2})$');
final _numericLabel = RegExp(r'^(?:[0-9]+|0[xX][0-9A-Fa-f]*)$');
final _ipv6Unit = RegExp(r'^[0-9A-Fa-f]{1,4}$');

_LinkParts? _parseLink(String value) {
  if (utf8.encode(value).length > 2048 || value.contains(r'\')) {
    return null;
  }
  for (final rune in value.runes) {
    if (rune <= 0x20 || rune == 0x7f) {
      return null;
    }
  }
  final schemeEnd = value.indexOf('://');
  if (schemeEnd < 0) {
    return null;
  }
  final scheme = value.substring(0, schemeEnd);
  final lowerScheme = _asciiLower(scheme);
  if (lowerScheme != 'http' && lowerScheme != 'https') {
    return null;
  }
  final authorityStart = schemeEnd + 3;
  var authorityEnd = value.length;
  for (final delimiter in const <String>['/', '?', '#']) {
    final index = value.indexOf(delimiter, authorityStart);
    if (index >= 0 && index < authorityEnd) {
      authorityEnd = index;
    }
  }
  final authority = value.substring(authorityStart, authorityEnd);
  final remainder = value.substring(authorityEnd);
  if (authority.isEmpty || authority.contains('@')) {
    return null;
  }

  final String port;
  if (authority.startsWith('[')) {
    final closing = authority.indexOf(']');
    if (closing < 0 || !_isValidIpv6(authority.substring(1, closing))) {
      return null;
    }
    port = authority.substring(closing + 1);
    if (port.isNotEmpty && !port.startsWith(':')) {
      return null;
    }
  } else {
    final colon = authority.indexOf(':');
    if (colon >= 0 && authority.lastIndexOf(':') != colon) {
      return null;
    }
    final host = colon < 0 ? authority : authority.substring(0, colon);
    port = colon < 0 ? '' : authority.substring(colon);
    if (!_isValidHost(host)) {
      return null;
    }
  }
  if (port.isNotEmpty && !_isValidPort(port.substring(1))) {
    return null;
  }

  final fragmentIndex = remainder.indexOf('#');
  final beforeFragment = fragmentIndex < 0
      ? remainder
      : remainder.substring(0, fragmentIndex);
  final fragment = fragmentIndex < 0
      ? ''
      : remainder.substring(fragmentIndex + 1);
  final queryIndex = beforeFragment.indexOf('?');
  final path = queryIndex < 0
      ? beforeFragment
      : beforeFragment.substring(0, queryIndex);
  if (!_validPercentEncoding(path) || !_validPercentEncoding(fragment)) {
    return null;
  }
  return _LinkParts(scheme, authority, remainder);
}

bool _isValidPort(String value) {
  if (value.isEmpty) {
    return true;
  }
  if (!_decimal.hasMatch(value)) {
    return false;
  }
  final parsed = int.tryParse(value);
  return parsed != null && parsed <= 65535;
}

bool _isValidHost(String host) {
  if (host.isEmpty) {
    return false;
  }
  for (final rune in host.runes) {
    if (rune < 128 &&
        !(_isAsciiLetter(rune) ||
            _isAsciiDigit(rune) ||
            rune == 0x2d ||
            rune == 0x2e ||
            rune == 0x5f ||
            rune == 0x7e)) {
      return false;
    }
  }
  final withoutTrailingDot = host.endsWith('.')
      ? host.substring(0, host.length - 1)
      : host;
  // 浏览器把末段为数字的主机名解析为 IPv4，因此它必须是规范的点分四段地址。
  if (_numericLabel.hasMatch(withoutTrailingDot.split('.').last)) {
    return !host.endsWith('.') && _isValidIpv4(withoutTrailingDot);
  }
  return true;
}

bool _isValidIpv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) {
    return false;
  }
  for (final part in parts) {
    if (!_ipv4Octet.hasMatch(part) || int.parse(part) > 255) {
      return false;
    }
  }
  return true;
}

bool _isValidIpv6(String value) {
  if (value.isEmpty || value.contains('%')) {
    return false;
  }
  final compression = value.indexOf('::');
  if (compression != value.lastIndexOf('::')) {
    return false;
  }
  if (compression < 0) {
    return _ipv6Units(value, ipv4Allowed: true) == 8;
  }
  final left = value.substring(0, compression);
  final right = value.substring(compression + 2);
  if (left.endsWith(':') || right.startsWith(':')) {
    return false;
  }
  final leftUnits = left.isEmpty ? 0 : _ipv6Units(left, ipv4Allowed: false);
  final rightUnits = right.isEmpty ? 0 : _ipv6Units(right, ipv4Allowed: true);
  return leftUnits >= 0 && rightUnits >= 0 && leftUnits + rightUnits < 8;
}

int _ipv6Units(String value, {required bool ipv4Allowed}) {
  if (value.isEmpty || value.startsWith(':') || value.endsWith(':')) {
    return -1;
  }
  final parts = value.split(':');
  var units = 0;
  for (var index = 0; index < parts.length; index++) {
    final part = parts[index];
    if (_ipv6Unit.hasMatch(part)) {
      units++;
      continue;
    }
    if (ipv4Allowed && index == parts.length - 1 && _isValidIpv4(part)) {
      units += 2;
      continue;
    }
    return -1;
  }
  return units;
}

bool _validPercentEncoding(String value) {
  for (var index = 0; index < value.length; index++) {
    if (value.codeUnitAt(index) != 0x25) {
      continue;
    }
    if (index + 2 >= value.length ||
        !_isHexDigit(value.codeUnitAt(index + 1)) ||
        !_isHexDigit(value.codeUnitAt(index + 2))) {
      return false;
    }
    index += 2;
  }
  return true;
}

bool _isAsciiLetter(int unit) =>
    (unit >= 0x41 && unit <= 0x5a) || (unit >= 0x61 && unit <= 0x7a);

bool _isAsciiDigit(int unit) => unit >= 0x30 && unit <= 0x39;

bool _isHexDigit(int unit) =>
    _isAsciiDigit(unit) ||
    (unit >= 0x41 && unit <= 0x46) ||
    (unit >= 0x61 && unit <= 0x66);

String _asciiLower(String value) {
  return String.fromCharCodes(
    value.codeUnits.map(
      (unit) => unit >= 0x41 && unit <= 0x5a ? unit + 0x20 : unit,
    ),
  );
}

final class _LinkParts {
  const _LinkParts(this.scheme, this.authority, this.remainder);

  final String scheme;
  final String authority;
  final String remainder;
}
