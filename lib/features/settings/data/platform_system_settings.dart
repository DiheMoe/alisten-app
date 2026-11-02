import 'dart:io';

import 'package:alisten/features/settings/application/system_settings.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

// Android 可经 Activity 直达本应用的通知设置页；iOS 没有直达地址，只能打开
// “设置”中本应用的页面。
final class PlatformSystemSettings implements SystemSettings {
  PlatformSystemSettings({bool? android, this._launch = launchUrl})
    : _android = android ?? Platform.isAndroid;

  static const _channel = MethodChannel('moe.dihe.alisten/system_settings');

  // 即 iOS 的 `UIApplication.openSettingsURLString`。
  static final _appSettings = Uri.parse('app-settings:');

  final bool _android;
  final Future<bool> Function(Uri uri) _launch;

  @override
  Future<bool> openNotificationSettings() async {
    try {
      if (_android) {
        return await _channel.invokeMethod<bool>('openNotificationSettings') ??
            false;
      }
      return await _launch(_appSettings);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
