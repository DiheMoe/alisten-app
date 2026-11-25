import 'dart:async';

import 'package:alisten/app/deep_link_controller.dart';
import 'package:alisten/app/feedback.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<bool> confirmLeavingRoom(BuildContext context) => showConfirmSheet(
  context,
  title: '退出这个房间？',
  message: '这台设备会停止播放，房间里的其他人照常收听。',
  confirmLabel: '退出房间',
  confirmIcon: AlistenIcons.signOut,
  // 面板收起后页面才能以动画离开。
  untilClosed: true,
);

void copyInviteLink(
  WidgetRef ref, {
  required String id,
  required String? slug,
}) {
  final link = ref
      .read(deepLinkControllerProvider)
      .inviteLink(id: id, slug: slug);
  unawaited(Clipboard.setData(ClipboardData(text: link)));
  ref.read(toastControllerProvider).show(ToastKind.success, '邀请链接已复制');
}

void reportVote(ToastController toasts, MutationResult<VoteSkipResult> result) {
  reportMutation(
    toasts,
    result,
    success: (vote) =>
        vote.skipped ? '已切歌' : '已投票 ${vote.votes}/${vote.requiredVotes}',
  );
}
