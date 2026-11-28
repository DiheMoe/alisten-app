import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class DesktopWindowControl {
  Future<bool> isMaximized();
  Future<void> startDragging();
  Future<void> showSystemMenu();
  Future<void> minimize();
  Future<void> toggleMaximize();
  Future<void> close();
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
