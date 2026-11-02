import 'dart:ui' show AppLifecycleState;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 平台首次报告生命周期之前按可见处理，因为此时应用正在前台启动。
final appVisibleProvider = NotifierProvider<AppVisibility, bool>(
  AppVisibility.new,
);

final class AppVisibility extends Notifier<bool> {
  @override
  bool build() => true;

  void follow(AppLifecycleState lifecycle) {
    state = lifecycle == AppLifecycleState.resumed;
  }
}
