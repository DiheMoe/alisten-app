import 'dart:ui' show AppLifecycleState;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 最近一次平台报告的生命周期；平台首次报告前按在前台处理。
final appLifecycleProvider = NotifierProvider<AppLifecycle, AppLifecycleState>(
  AppLifecycle.new,
);

final class AppLifecycle extends Notifier<AppLifecycleState> {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;

  void report(AppLifecycleState lifecycle) => state = lifecycle;
}

/// 平台首次报告生命周期之前按可见处理，因为此时应用正在前台启动。
final appVisibleProvider = NotifierProvider<AppVisibility, bool>(
  AppVisibility.new,
);

final class AppVisibility extends Notifier<bool> {
  @override
  bool build() => ref.watch(appLifecycleProvider) == AppLifecycleState.resumed;

  void follow(AppLifecycleState lifecycle) {
    ref.read(appLifecycleProvider.notifier).report(lifecycle);
  }
}
