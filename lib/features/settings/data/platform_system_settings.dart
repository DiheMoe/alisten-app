import 'dart:io';

import 'package:alisten/features/settings/application/system_settings.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

// Android 可经 Activity 直达本应用的通知设置页；iOS 没有直达地址，只能打开
// “设置”中本应用的页面。
final class PlatformSystemSettings implements SystemSettings {
  PlatformSystemSettings({
    bool? android,
    bool? windows,
    this._launch = launchUrl,
  }) : _android = android ?? Platform.isAndroid,
       _windows = windows ?? Platform.isWindows;

  static const _channel = MethodChannel('moe.dihe.alisten/system_settings');
  static const _windowChannel = MethodChannel('moe.dihe.alisten/window');

  // 即 iOS 的 `UIApplication.openSettingsURLString`。
  static final _appSettings = Uri.parse('app-settings:');

  final bool _android;
  final bool _windows;
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

  @override
  Future<void> setMinimizeToTrayOnClose(bool enabled) async {
    if (!_windows) return;
    try {
      await _windowChannel.invokeMethod<void>(
        'setMinimizeToTrayOnClose',
        enabled,
      );
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}
