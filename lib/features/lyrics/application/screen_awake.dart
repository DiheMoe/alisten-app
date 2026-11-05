import 'dart:async';

import 'package:alisten/core/logging/app_log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ScreenAwakeDevice {
  Future<void> setKeptOn({required bool on});
}

final screenAwakeDeviceProvider = Provider<ScreenAwakeDevice>((ref) {
  throw UnimplementedError('screenAwakeDevice 未注入');
});

final screenAwakeProvider = Provider<ScreenAwake>((ref) {
  return ScreenAwake(ref.watch(screenAwakeDeviceProvider));
});

/// 按持有者计数：旋转或切换布局时新旧页面短暂共存，旧页面销毁时不能关掉新页面的
/// 常亮。
final class ScreenAwake {
  ScreenAwake(this._device);

  final ScreenAwakeDevice _device;
  int _holders = 0;

  void hold() {
    if (++_holders == 1) unawaited(_keepOn(on: true));
  }

  void release() {
    if (--_holders == 0) unawaited(_keepOn(on: false));
  }

  // 只影响会不会熄屏，失败了也不该打断播放。
  Future<void> _keepOn({required bool on}) async {
    try {
      await _device.setKeptOn(on: on);
    } on Object catch (error) {
      AppLog.debug(
        'lyrics',
        'screen not kept on',
        type: '${error.runtimeType}',
      );
    }
  }
}
