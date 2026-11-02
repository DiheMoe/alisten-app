import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// 字段只能是错误码、计数、时长、协议类型名或枚举值；有意不接受服务端消息、
/// 错误对象、地址或 map 参数，载荷和凭据因此无从写入。`event` 必须是代码中
/// 写定的固定描述。
abstract final class AppLog {
  static const _release = bool.fromEnvironment('dart.vm.product');

  @visibleForTesting
  static void Function(String name, int level, String message)? onRecord;

  static void debug(
    String source,
    String event, {
    String? type,
    String? code,
    int? closeCode,
    int? attempt,
    Duration? delay,
    Enum? outcome,
  }) {
    if (_release) return;
    _write(500, source, event, type, code, closeCode, attempt, delay, outcome);
  }

  static void info(
    String source,
    String event, {
    String? type,
    String? code,
    int? closeCode,
    int? attempt,
    Duration? delay,
    Enum? outcome,
  }) {
    _write(800, source, event, type, code, closeCode, attempt, delay, outcome);
  }

  static void warn(
    String source,
    String event, {
    String? type,
    String? code,
    int? closeCode,
    int? attempt,
    Duration? delay,
    Enum? outcome,
  }) {
    _write(900, source, event, type, code, closeCode, attempt, delay, outcome);
  }

  static void error(
    String source,
    String event, {
    String? type,
    String? code,
    int? closeCode,
    int? attempt,
    Duration? delay,
    Enum? outcome,
  }) {
    _write(1000, source, event, type, code, closeCode, attempt, delay, outcome);
  }

  static void _write(
    int level,
    String source,
    String event,
    String? type,
    String? code,
    int? closeCode,
    int? attempt,
    Duration? delay,
    Enum? outcome,
  ) {
    final fields = [
      if (type != null) 'type=$type',
      if (code != null) 'code=$code',
      if (closeCode != null) 'closeCode=$closeCode',
      if (attempt != null) 'attempt=$attempt',
      if (delay != null) 'delayMs=${delay.inMilliseconds}',
      if (outcome != null) 'outcome=${outcome.name}',
    ];
    final message = fields.isEmpty ? event : '$event ${fields.join(' ')}';
    onRecord?.call('alisten.$source', level, message);
    developer.log(message, name: 'alisten.$source', level: level);
  }
}
