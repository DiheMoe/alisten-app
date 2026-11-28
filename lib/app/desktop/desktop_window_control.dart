import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class DesktopWindowControl {
  Future<bool> isMaximized();
  Future<void> startDragging();
  Future<void> showSystemMenu();
  Future<void> minimize();
  Future<void> toggleMaximize();
  Future<void> close();

  /// 窗口收在托盘里或被最小化时把它显示出来。
  Future<void> show();
  void listenMaximized(ValueChanged<bool>? onChanged);
}

final desktopWindowControlProvider = Provider<DesktopWindowControl>(
  (ref) => const MethodChannelWindowControl(),
);

final class MethodChannelWindowControl implements DesktopWindowControl {
  const MethodChannelWindowControl();

  static const _channel = MethodChannel('moe.dihe.alisten/window');

  @override
  Future<bool> isMaximized() async =>
      await _channel.invokeMethod<bool>('isMaximized') ?? false;

  @override
  Future<void> startDragging() => _channel.invokeMethod('startDragging');

  @override
  Future<void> showSystemMenu() => _channel.invokeMethod('showSystemMenu');

  @override
  Future<void> minimize() => _channel.invokeMethod('minimizeWindow');

  @override
  Future<void> toggleMaximize() => _channel.invokeMethod('toggleMaximize');

  @override
  Future<void> close() => _channel.invokeMethod('closeWindow');

  @override
  Future<void> show() => _channel.invokeMethod('showWindow');

  @override
  void listenMaximized(ValueChanged<bool>? onChanged) {
    if (onChanged == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'maximizedChanged' && call.arguments is bool) {
        onChanged(call.arguments as bool);
      }
    });
  }
}
