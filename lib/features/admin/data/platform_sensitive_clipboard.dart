import 'dart:io';

import 'package:alisten/features/admin/application/sensitive_clipboard.dart';
import 'package:flutter/services.dart';

// Flutter 的 `Clipboard.setData` 无法添加敏感标记，Android 上由 Activity 写入
// 剪贴板；iOS 没有对应标记，按普通文本复制。
final class PlatformSensitiveClipboard implements SensitiveClipboard {
  PlatformSensitiveClipboard({bool? android})
    : _android = android ?? Platform.isAndroid;

  static const _channel = MethodChannel('moe.dihe.alisten/clipboard');

  final bool _android;

  @override
  Future<void> copy(String text) async {
    if (!_android) {
      await Clipboard.setData(ClipboardData(text: text));
      return;
    }
    final bool? copied;
    try {
      copied = await _channel.invokeMethod<bool>('setSensitiveText', {
        'text': text,
      });
    } on PlatformException {
      throw StateError('sensitive text not copied');
    } on MissingPluginException {
      throw StateError('sensitive text not copied');
    }
    if (copied != true) throw StateError('sensitive text not copied');
  }
}
