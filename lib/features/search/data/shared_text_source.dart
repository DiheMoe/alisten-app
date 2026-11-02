import 'dart:io';

import 'package:alisten/features/search/application/shared_link.dart';
import 'package:flutter/services.dart';

// 只有 Android 的 Activity 会转发其他应用分享来的文本；其他平台没有该通道的
// 原生实现，所以不监听。
final class PlatformSharedTextSource implements SharedTextSource {
  PlatformSharedTextSource({bool? android})
    : _android = android ?? Platform.isAndroid;

  static const _channel = EventChannel('moe.dihe.alisten/shared_text');

  final bool _android;

  @override
  late final Stream<String> texts = _android
      ? _channel.receiveBroadcastStream().where((text) => text is String).cast()
      : const Stream.empty();
}
