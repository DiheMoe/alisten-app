import 'dart:async';

import 'package:alisten/app/feedback.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const shareWaitsText = '进入房间后可点这首歌';

const _sharesUnreadable = '没能读取分享的内容';

const _logSource = 'share';

void listenForShares(WidgetRef ref) {
  final toasts = ref.read(toastControllerProvider);
  final shares = ref.read(pendingShareControllerProvider.notifier);
  var sheetShown = false;
  ref.listenManual<PendingShare?>(
    pendingShareControllerProvider,
    (previous, next) {
      if (next == null) return;
      final arrived = next.id != previous?.id;
      if (next.roomId != null) {
        // 等待过的分享已显示在点歌页上时，不再弹出面板。
        final offered =
            arrived || (previous!.roomId == null && !_songSearchShows(ref));
        // 已经弹出的面板会显示最新的分享。
        if (offered && !sheetShown) {
          sheetShown = true;
          unawaited(
            _showSheet(
              ref,
              toasts,
              shares,
            ).whenComplete(() => sheetShown = false),
          );
        }
        return;
      }
      // 分享的文字解析完成之后只提示一次。
      if (!next.resolved || (!arrived && previous!.resolved)) return;
      final share = next.share;
      final reason = share == null ? noLinkText : unpickableReason(share, null);
      if (reason == null) {
        toasts.show(ToastKind.info, shareWaitsText);
        return;
      }
      toasts.show(ToastKind.warning, reason);
      // 正在通知分享变化时不能修改它。
      unawaited(Future.microtask(() => shares.dismiss(next.id)));
    },
    // 启动时就失败（如没有分享来源）也要提示并记录，不能悄悄漏掉。
    // 错误可能带有分享的链接，提示和日志都不使用它。
    fireImmediately: true,
    onError: (error, _) {
      AppLog.error(_logSource, 'shares not followed');
      toasts.show(ToastKind.warning, _sharesUnreadable);
    },
  );
  // 运行中的读取错误已由分享的所有者记录，这里只提示用户。
  ref.listenManual<int>(
    shareReadFailuresProvider,
    (_, _) => toasts.show(ToastKind.warning, _sharesUnreadable),
  );
}

// 点歌页和其上的歌单页叠在房间页之上，路由器报告的位置不含它们，
// 只有最后一个匹配含有。按路由模板而不是位置判断：
// 房间别名可能恰好是 `search` 或 `playlists`。
bool _songSearchShows(WidgetRef ref) {
  final matches = ref.read(routerProvider).routerDelegate.currentConfiguration;
  if (matches.isEmpty) return false;
  final path = matches.last.route.path;
  return path == songSearchSegment || path == playlistSegment;
}

Future<void> _showSheet(
  WidgetRef ref,
  ToastController toasts,
  PendingShareController shares,
) async {
  final router = ref.read(routerProvider);
  final context = router.routerDelegate.navigatorKey.currentContext;
  // 第一个页面出现之前无法弹出面板，分享改为等点歌页显示。
  if (context == null) return;
  // 关闭面板时丢弃它显示的最新分享。
  var shown = ref.read(pendingShareControllerProvider)?.id;
  final showing = ref.listenManual(pendingShareControllerProvider, (_, next) {
    if (next != null) shown = next.id;
  });
  try {
    await showSheetPanel<void>(
      context,
      builder: (_) => ShareConfirmSheet(
        onResult: (result, success) =>
            reportMutation(toasts, result, success: (_) => success),
      ),
    );
  } finally {
    showing.close();
  }
  final id = shown;
  if (id != null) shares.dismiss(id);
}

class ShareConfirmSheet extends ConsumerWidget {
  const ShareConfirmSheet({required this.onResult, super.key});

  final QueueResultCallback onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(pendingShareControllerProvider, (_, next) {
      // 分享已点或在别处被丢弃时关闭面板。
      if (next == null) dismissSheet(context);
    });
    final pending = ref.watch(pendingShareControllerProvider);
    final roomName = ref.watch(
      roomControllerProvider.select((room) => room.roomName),
    );
    if (pending == null) return const SizedBox.shrink();
    final shares = ref.read(pendingShareControllerProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShareLinkCard(
          heading: sharedLinkHeading,
          share: pending.share,
          resolving: !pending.resolved,
          roomName: roomName ?? '当前房间',
          onResult: onResult,
          onPicked: () => shares.dismiss(pending.id),
          framed: false,
        ),
        const PickUnavailableNotice(
          padding: EdgeInsets.only(top: AlistenSpacing.sm),
        ),
        const SizedBox(height: AlistenSpacing.xs),
        PillButton(
          label: '取消',
          style: PillButtonStyle.ghost,
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
