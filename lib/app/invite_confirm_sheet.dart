import 'dart:async';

import 'package:alisten/app/feedback.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/server/invite_link.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logSource = 'invite';

/// 同一时间最多处理一个邀请、显示一个面板；处理期间到达的邀请排队，
/// 只保留最新的一个。
void listenForInvites(
  WidgetRef ref, {
  required void Function(String route) openRoute,
}) {
  final offers = ref.read(inviteOfferControllerProvider.notifier);
  var following = false;
  Future<void> follow(InviteOffer first) async {
    following = true;
    try {
      InviteOffer? offer = first;
      while (offer != null) {
        try {
          await _follow(ref, offer.target, openRoute);
        } on Object catch (error) {
          AppLog.warn(
            _logSource,
            'invite not followed',
            type: '${error.runtimeType}',
          );
        }
        if (!ref.context.mounted) return;
        offers.dismiss(offer.id);
        if (ref.read(inviteOfferControllerProvider) == null) return;
        // 上一个邀请可能刚跳转路由，新页面下一帧才建好，
        // 在此之前弹出的面板会被它盖住。
        await SchedulerBinding.instance.endOfFrame;
        if (!ref.context.mounted) return;
        offer = ref.read<InviteOffer?>(inviteOfferControllerProvider);
      }
    } finally {
      following = false;
    }
  }

  ref.listenManual<InviteOffer?>(inviteOfferControllerProvider, (
    previous,
    next,
  ) {
    if (next == null || next.id == previous?.id || following) return;
    unawaited(follow(next));
  });
}

Future<void> _follow(
  WidgetRef ref,
  InviteTarget offered,
  void Function(String route) openRoute,
) async {
  final recognizer = ref.read(inviteRecognizerProvider);
  final target = await recognizer.refresh(offered);
  if (target == null || !ref.context.mounted) return;
  final ServerProfile server;
  final String title;
  final String message;
  final String confirmLabel;
  final opensPlaylist = target.link.kind == SiteLinkKind.sharedPlaylist;
  switch (target) {
    case InviteToCurrent(isActiveRoom: true):
      return;
    case InviteToCurrent(:final route):
      openRoute(route);
      return;
    case InviteToSaved(server: final saved):
      server = saved;
      final directory = ref.read(serverDirectoryProvider);
      title = opensPlaylist
          ? '切换到 ${server.displayName} 并打开歌单？'
          : '切换到 ${server.displayName} 并进入房间？';
      message = '服务器：${directory.linkAuthorityOf(server)}。切换后会退出当前房间。';
      confirmLabel = opensPlaylist ? '切换并打开' : '切换并进入';
    case InviteToNew(server: final added):
      server = added;
      title = opensPlaylist
          ? '添加 ${server.displayName} 并打开歌单？'
          : '添加 ${server.displayName} 并进入房间？';
      message = '服务器：${server.authority}。添加后会切换到这个服务器，并退出当前房间。';
      confirmLabel = opensPlaylist ? '添加并打开' : '添加并进入';
  }
  final navigator = ref.read(routerProvider).routerDelegate.navigatorKey;
  // 应用刚启动时第一个页面可能还没有建好。
  if (navigator.currentContext == null) {
    await SchedulerBinding.instance.endOfFrame;
  }
  final context = navigator.currentContext;
  if (context == null || !context.mounted) {
    AppLog.warn(_logSource, 'invite not shown');
    return;
  }
  final toasts = ref.read(toastControllerProvider);
  final closed = Completer<void>();
  ProbeFailure? incompatible;
  // 确认后会离开当前页面，须等面板收起，否则下方页面不播放退出动画。
  final confirmed = await showConfirmSheet(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    untilClosed: true,
    busyLabel: '正在检查服务器…',
    onConfirm: target is InviteToNew
        ? () async {
            incompatible = await recognizer.checkVersion(
              target,
              cancel: closed.future,
            );
            return incompatible == null;
          }
        : null,
  );
  // 中途取消时面板已关闭而检查仍在进行，通知检查关闭连接。
  closed.complete();
  if (incompatible case final failure?) {
    toasts.show(ToastKind.failure, probeFailureText(failure));
    return;
  }
  if (!confirmed || !context.mounted) return;
  final switched = await switchServerFlow(
    context,
    ref,
    server,
    onNotice: toasts.show,
  );
  if (switched && context.mounted) openRoute(target.route);
}
