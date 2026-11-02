import 'dart:async';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/invite_link.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logSource = 'share';

@immutable
final class PendingShare {
  const PendingShare({
    required this.id,
    required this.roomId,
    this.resolved = false,
    this.share,
  });

  /// 每次分享都递增，同一文本分享两次也算两次。
  final int id;

  /// 分享时所在的房间；当时不在房间里则为之后第一个打开的房间，在此之前为
  /// null。点歌页不论有没有房间都显示这条分享。
  final String? roomId;

  /// 为 true 时识别已完成，此时 [share] 为 null 表示文本里没有链接。
  final bool resolved;
  final ResolvedShare? share;
}

/// 读取分享内容时的出错次数。错误本身可能带有分享的内容，所以只暴露次数。
final shareReadFailuresProvider = NotifierProvider<ShareReadFailures, int>(
  ShareReadFailures.new,
);

final class ShareReadFailures extends Notifier<int> {
  @override
  int build() => 0;

  void report() => state++;
}

final pendingShareControllerProvider =
    NotifierProvider<PendingShareController, PendingShare?>(
      PendingShareController.new,
    );

final class PendingShareController extends Notifier<PendingShare?> {
  int _lastId = 0;

  @override
  PendingShare? build() {
    final texts = ref.watch(sharedTextSourceProvider).texts;
    final subscription = texts.listen(
      (text) => unawaited(_receive(text)),
      onError: (Object error) {
        AppLog.warn(
          _logSource,
          'shared text not received',
          type: '${error.runtimeType}',
        );
        ref.read(shareReadFailuresProvider.notifier).report();
      },
    );
    ref.onDispose(subscription.cancel);
    ref.listen(
      roomControllerProvider.select(
        (room) =>
            room.status == RoomConnectionStatus.open ? room.activeRoomId : null,
      ),
      (_, roomId) {
        if (roomId != null) _offerTo(roomId);
      },
    );
    return null;
  }

  void _offerTo(String roomId) {
    final pending = state;
    if (pending == null || pending.roomId != null) return;
    state = PendingShare(
      id: pending.id,
      roomId: roomId,
      resolved: pending.resolved,
      share: pending.share,
    );
  }

  Future<void> _receive(String text) async {
    final id = ++_lastId;
    // 先识别邀请再保留分享，否则房间里弹出的分享面板会在邀请确认面板之下留成
    // 空白。
    final invite = await ref.read(inviteRecognizerProvider).recognize(text);
    if (!ref.mounted || id != _lastId) return;
    if (invite != null) {
      state = null;
      ref.read(inviteOfferControllerProvider.notifier).offer(invite);
      return;
    }
    final roomId = ref.read(roomControllerProvider).activeRoomId;
    state = PendingShare(id: id, roomId: roomId);
    final ResolvedShare? share;
    try {
      share = await ref.read(linkResolverProvider).resolve(text);
    } on Object {
      AppLog.warn(_logSource, 'shared text not resolved');
      dismiss(id);
      return;
    }
    final pending = state;
    if (!ref.mounted || pending?.id != id) return;
    state = PendingShare(
      id: id,
      roomId: pending!.roomId,
      resolved: true,
      share: share,
    );
  }

  void dismiss(int id) {
    if (ref.mounted && state?.id == id) state = null;
  }
}
