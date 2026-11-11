import 'dart:math' as math;
import 'dart:typed_data';

const invalidPairingCodeText = '配对码是 8 位字母和数字，不含 0、O、1、I。';

// 与协议的 PairingCode 一致：数字 2–9 和除 I、O 以外的大写字母。
final _pairingCode = RegExp(r'^[2-9A-HJ-NP-Z]{8}$');
final _separators = RegExp(r'[\s-]');

final class PairingCode {
  const PairingCode({
    required this.code,
    required this.expiresAtMs,
    this.qrPng,
  });

  final String code;
  final int expiresAtMs;

  /// 为 null 表示二维码没能解码，只显示 8 位码。
  final Uint8List? qrPng;
}

/// 手动输入常带空格、连字符或小写字母，链接片段里的配对码也可能被转义过。
String normalizePairingCode(String input) {
  final text = _decoded(input) ?? input;
  return text.toUpperCase().replaceAll(_separators, '');
}

String? _decoded(String input) {
  try {
    return Uri.decodeComponent(input);
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}

bool isPairingCode(String code) => _pairingCode.hasMatch(code);

/// 分成两组，照着输入时不容易看串。
String formatPairingCode(String code) =>
    code.length <= 4 ? code : '${code.substring(0, 4)}-${code.substring(4)}';

/// 读屏逐字读出，不把两组各读成一个词。
String spokenPairingCode(String code) => '配对码 ${code.split('').join(' ')}';

int pairingSecondsLeft(int expiresAtMs, int nowMs) =>
    math.max(0, ((expiresAtMs - nowMs) / 1000).ceil());

String pairingCountdownText(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
