import 'dart:async';

import 'package:alisten/features/room/index.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app_test_harness.dart';

const _waiting = '连接中断，稍后自动重连';

void main() {
  Future<void> platformReports(
    WidgetTester tester,
    AppLifecycleState state,
  ) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.lifecycle.name,
      SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
      (_) {},
    );
    await tester.pump();
  }

  // 让连接事件送达、状态行展开完；推进的时间远小于重连倒计时。
  Future<void> frame(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  // 倒计时随测试时间推进，不依赖真实时钟。
  Future<EnteredRoom> enter(WidgetTester tester) {
    return enterRoom(
      tester,
      overrides: [
        roomNowProvider.overrideWithValue(() => tester.binding.clock.now()),
      ],
    );
  }

  bool offersRetry(WidgetTester tester) {
    final node = tester.getSemantics(find.bySemanticsLabel(_waiting));
    return node.flagsCollection.isButton;
  }

  testWidgets('back in the foreground while a reconnect is under way, 立即重试 '
      'is offered again once that attempt fails, and reconnects once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (:rooms, router: _, settle: _) = await enter(tester);
    final transport = rooms.last;
    transport.disconnect();
    await frame(tester);
    expect(offersRetry(tester), isTrue);
    expect(find.textContaining('3 秒后重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('2 秒后重试'), findsOneWidget);

    await tester.tap(find.textContaining('秒后重试'));
    await frame(tester);
    expect(transport.connectAttempts, 2);
    transport.disconnect();
    await frame(tester);
    expect(offersRetry(tester), isFalse, reason: 'one retry per disconnect');

    // 下一次尝试仍在进行时，应用离开前台又回来。
    await tester.pump(transport.retryIn);
    expect(transport.connectAttempts, 3);
    await platformReports(tester, AppLifecycleState.paused);
    await platformReports(tester, AppLifecycleState.resumed);
    expect(transport.connectAttempts, 3, reason: 'an attempt is under way');
    transport.disconnect();
    await frame(tester);
    expect(offersRetry(tester), isTrue);

    await tester.tap(find.textContaining('秒后重试'));
    await frame(tester);
    expect(transport.connectAttempts, 4);
    unawaited(transport.stop());
    semantics.dispose();
  });

  testWidgets('a room page opened again after the one retry was used offers '
      'none', (tester) async {
    final semantics = tester.ensureSemantics();
    final (:rooms, :router, settle: _) = await enter(tester);
    final transport = rooms.last;
    transport.disconnect();
    await frame(tester);
    await tester.tap(find.textContaining('秒后重试'));
    await frame(tester);
    transport.disconnect();
    await frame(tester);

    // 往返须在重连倒计时结束之前完成。
    Future<void> go(String location) async {
      router.go(location);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await go('/');
    await go('/r/listen');

    expect(find.textContaining('秒后重试'), findsOneWidget);
    expect(offersRetry(tester), isFalse);
    final attempts = transport.connectAttempts;
    await tester.tap(find.textContaining('秒后重试'));
    await tester.pump();
    expect(transport.connectAttempts, attempts);
    unawaited(transport.stop());
    semantics.dispose();
  });
}
