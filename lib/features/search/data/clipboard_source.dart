import 'dart:io';

import 'package:alisten/features/search/application/clipboard_link_controller.dart';
import 'package:flutter/services.dart';

// Android 从剪贴板描述读取最后一次变化的时间，读描述不会像 Android 12 及以上
// 读内容那样弹出系统提示。iOS 每次读取都询问用户，也不提供变化时间，所以 iOS
// 上没有标记，应用也不会自行读取剪贴板。
final class PlatformClipboardSource implements ClipboardSource {
  PlatformClipboardSource({bool? android})
    : _android = android ?? Platform.isAndroid;

  static const _channel = MethodChannel('moe.dihe.alisten/clipboard');

  final bool _android;

  @override
  Future<int?> stamp() async {
    if (!_android) return null;
    try {
      return await _channel.invokeMethod<int>('primaryClipStamp');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<String?> read() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on PlatformException {
      return null;
    }
  }
}
