import 'dart:async';

import 'package:alisten/features/update/application/update_controller.dart';
import 'package:alisten/features/update/presentation/update_sheet.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 调用方的页面可能先离开，面板因此由根导航器弹出。[onNotice] 必须比调用方存活
/// 更久。
Future<void> checkForUpdate(
  BuildContext context,
  WidgetRef ref, {
  required void Function(ToastKind kind, String text) onNotice,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final result = await ref.read(updateControllerProvider.notifier).checkNow();
  switch (result) {
    case null:
      return;
    case UpdateAvailable():
      if (navigator.mounted) {
        unawaited(
          showUpdateSheet(navigator.context, result, onNotice: onNotice),
        );
      }
    case UpToDate():
      onNotice(ToastKind.info, '已是最新版本');
    case UpdateCheckFailed():
      onNotice(ToastKind.failure, '检查更新失败，请稍后再试。');
  }
}
