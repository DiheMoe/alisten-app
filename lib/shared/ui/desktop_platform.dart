import 'package:flutter/foundation.dart';

// 发布构建里按目标系统算成常量，桌面专用的界面不会编进手机的安装包。
@pragma('vm:platform-const-if', !kDebugMode)
bool get isDesktopPlatform {
  final platform = defaultTargetPlatform;
  return platform == TargetPlatform.linux ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.macOS;
}

@pragma('vm:platform-const-if', !kDebugMode)
bool get isWindowsDesktop => defaultTargetPlatform == TargetPlatform.windows;
