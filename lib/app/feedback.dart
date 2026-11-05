import 'dart:async';

import 'package:alisten/features/chat/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final toastControllerProvider = Provider<ToastController>((ref) {
  final controller = ToastController();
  ref.onDispose(controller.dispose);
  return controller;
});

const mutationUnknownText = '结果未知，已重新同步';

void copySongTitle(ToastController toasts, String title) {
  unawaited(Clipboard.setData(ClipboardData(text: title)));
  unawaited(HapticFeedback.mediumImpact());
  toasts.show(ToastKind.success, '已复制歌名');
}

void showMutationFeedback<T>(
  WidgetRef ref,
  MutationResult<T> result, {
  required String success,
}) {
  reportMutation(
    ref.read(toastControllerProvider),
    result,
    success: (_) => success,
  );
}

/// 页面可能在答复到达前销毁：调用方须在发出变更前取得 [toasts]。
void reportMutation<T>(
  ToastController toasts,
  MutationResult<T> result, {
  required String Function(T value) success,
}) {
  switch (result) {
    case MutationSucceeded(:final value):
      toasts.show(ToastKind.success, success(value));
    case MutationFailed(:final message):
      toasts.show(ToastKind.failure, message);
    case MutationUnknown():
      toasts.show(ToastKind.warning, mutationUnknownText);
    case MutationNotSent(:final message):
      toasts.show(ToastKind.warning, message);
  }
}

void listenForNotices(WidgetRef ref) {
  final toasts = ref.read(toastControllerProvider);
  ref.listenManual(
    identityControllerProvider.select((identity) => identity.notice),
    (_, notice) {
      if (notice == null) return;
      toasts.show(ToastKind.warning, notice);
      // 监听器可能在构建期间触发，此时不能修改状态。
      unawaited(
        Future.microtask(() {
          if (!ref.context.mounted) return;
          ref.read(identityControllerProvider.notifier).clearNotice();
        }),
      );
    },
    fireImmediately: true,
  );
  ref.listenManual(chatControllerProvider, (previous, next) {
    final notice = next.failureNotice;
    if (notice != null && next.failureNoticeId != previous?.failureNoticeId) {
      toasts.show(ToastKind.failure, notice);
    }
  });
}
