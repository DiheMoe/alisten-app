import 'dart:async';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/history/play_record.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/history/application/history_controller.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 由应用根节点保持存活，无论显示哪个页面、是否打开过播放历史页都会记录。
final historyRecorderProvider = Provider<HistoryRecorder>((ref) {
  final recorder = HistoryRecorder._(ref);
  // 监听 [roomControllerProvider] 而不是 nowPlayingProvider：应用不绘制帧时
  // （例如在后台），派生 provider 的变化不保证能在 Widget 构建之外送达。
  ref.listen(
    roomControllerProvider.select(
      (room) =>
          (room: room.snapshot?.room, nowPlaying: room.snapshot?.nowPlaying),
    ),
    (_, next) => recorder._onPlayback(next.room, next.nowPlaying),
    // 记录器启动时已在播放的歌也要记录，按播放标识去重。
    fireImmediately: true,
  );
  return recorder;
});

final class HistoryRecorder {
  HistoryRecorder._(this._ref);

  final Ref _ref;

  String? _playing;

  void _onPlayback(RoomInfo? room, NowPlaying? nowPlaying) {
    final identity = room == null || nowPlaying == null
        ? null
        : '${room.id}/${nowPlaying.entry.id}@${nowPlaying.startedAtMs}';
    if (identity == _playing) return;
    // 关闭记录期间也要更新，这样期间开始的歌在重新开启记录后不会补记。
    _playing = identity;
    if (nowPlaying == null || room == null) return;
    if (!_ref.read(settingsControllerProvider).value.recordHistory) return;
    final record = PlayRecord(
      roomId: room.id,
      roomName: room.name,
      serverOrigin: _ref.read(currentServerProvider).origin,
      track: nowPlaying.entry.track,
      meta: nowPlaying.entry.meta,
      playedAtMs: _ref.read(historyNowProvider)(),
    );
    // 不立即保存：启动时看到的播放发生在 provider 初始化期间，此时还不能修改
    // 播放历史。
    scheduleMicrotask(() => unawaited(_record(record)));
  }

  Future<void> _record(PlayRecord record) async {
    try {
      await _ref.read(historyControllerProvider.notifier).record(record);
    } on Object {
      AppLog.warn('history', 'play record not saved');
    }
  }
}
