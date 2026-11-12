import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../domain/room/room_fixtures.dart';
import 'app_test_harness.dart';

/// 播放进度和 Android 上闪烁的输入框光标每半秒刷新一次，1 秒内各占最多 2 帧；
/// 调试构建中 Riverpod 每次通知状态还会多排一帧，同样每半秒一次。
const periodicFrames = 4;

/// 房间页的背景每秒约 30 帧，另加半秒一次的刷新。
const roomPageFrames = 21 + periodicFrames;

/// 先让进出场动画、提示等有时限的变化结束，再以 120 Hz 的节奏推进 1 秒，返回
/// 其间实际画出的帧数。
Future<int> idleFrames(WidgetTester tester) async {
  for (var second = 0; second < 8; second++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump();
  const vsync = Duration(microseconds: 8333);
  var frames = 0;
  var counting = true;
  void count(Duration _) {
    if (!counting) return;
    frames++;
    tester.binding.addPostFrameCallback(count);
  }

  tester.binding.addPostFrameCallback(count);
  for (var elapsed = Duration.zero; elapsed < const Duration(seconds: 1);) {
    await tester.pump(vsync);
    elapsed += vsync;
  }
  counting = false;
  return frames;
}

Future<({GoRouter router, Future<void> Function() settle})> enterBusyRoom(
  WidgetTester tester, {
  String? lyricWords,
}) async {
  final (:rooms, :router, :settle) = await enterRoom(
    tester,
    nowPlaying: NowPlaying(
      entry: testQueueEntry,
      mediaUrl: '/media/netease/track-id',
      startedAtMs: 1000000,
      durationMs: 180000,
      gain: 1,
      lyric:
          '[00:00.00]第一行\n[00:04.00]第二行\n[00:08.00]第三行\n'
          '[00:12.00]第四行\n[00:16.00]第五行',
      lyricWords: lyricWords,
    ),
    serverNow: 1002000,
  );
  for (var seq = 2; seq < 6; seq++) {
    rooms.last.emit(
      RoomEventReceived(
        ChatMessageEvent(
          term: 1,
          seq: seq,
          member: testMember,
          content: '消息 $seq',
          sentAtMs: 1000000 + seq,
        ),
      ),
    );
  }
  await settle();
  return (router: router, settle: settle);
}
