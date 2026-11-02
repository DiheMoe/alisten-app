import 'dart:ui' show AppLifecycleState;

import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback_test_doubles.dart';

// 不初始化 Flutter binding：应用是否可见只能来自应用壳更新的 provider。
void main() {
  test('a start reminder is told whether the app is visible as the app shell '
      'last reported it', () {
    fakeAsync((async) {
      final h = PlaybackHarness(async);
      NowPlaying track(String id, int startedAtMs) =>
          nowPlayingWith(entryId: id, startedAtMs: startedAtMs);
      final second = track('second', trackStart + 60000);
      final third = track('third', trackStart + 120000);
      h.transport.emitHello(
        snapshotWith(nowPlayingWith(durationMs: 60000))
            .copyWith(term: 1, seq: 1, items: [second.entry, third.entry]),
        trackStart + 20000,
      );
      async.elapse(const Duration(seconds: 40));
      final visibility = h.container.read(appVisibleProvider.notifier);

      visibility.follow(AppLifecycleState.paused);
      h.play(second);
      async.elapse(const Duration(seconds: 60));
      visibility.follow(AppLifecycleState.resumed);
      h.play(third);
      async.flushMicrotasks();

      expect(h.reminder.entryIds, ['second', 'third']);
      expect(h.reminder.visibility, [false, true]);
      h.dispose();
    });
  });
}
