import 'dart:async';
import 'dart:convert';

import 'package:alisten/app/router.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/history/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/admin/admin_test_doubles.dart';
import '../features/lobby/lobby_test_doubles.dart';
import '../features/room/room_test_doubles.dart';
import 'app_test_harness.dart';

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

  testWidgets('animations pause while the app is not in the foreground', (
    tester,
  ) async {
    await pumpAlistenApp(tester);
    bool ticking() =>
        TickerMode.valuesOf(tester.element(find.text(emptyLobbyText))).enabled;

    expect(ticking(), isTrue);

    await platformReports(tester, AppLifecycleState.inactive);
    expect(ticking(), isFalse);

    await platformReports(tester, AppLifecycleState.paused);
    expect(ticking(), isFalse);

    await platformReports(tester, AppLifecycleState.resumed);
    expect(ticking(), isTrue);
  });

  testWidgets('animations follow whether the app is visible, with no state '
      'of their own', (tester) async {
    await pumpAlistenApp(tester);
    final visibility = appContainer(tester).read(appVisibleProvider.notifier);
    bool ticking() =>
        TickerMode.valuesOf(tester.element(find.text(emptyLobbyText))).enabled;

    visibility.follow(AppLifecycleState.paused);
    await tester.pump();
    expect(ticking(), isFalse);

    visibility.follow(AppLifecycleState.resumed);
    await tester.pump();
    expect(ticking(), isTrue);
  });

  testWidgets('whether the app is visible follows what the platform reports', (
    tester,
  ) async {
    await pumpAlistenApp(tester);
    final container = appContainer(tester);
    expect(container.read(appVisibleProvider), isTrue);

    await platformReports(tester, AppLifecycleState.inactive);
    expect(container.read(appVisibleProvider), isFalse);

    await platformReports(tester, AppLifecycleState.hidden);
    await platformReports(tester, AppLifecycleState.paused);
    expect(container.read(appVisibleProvider), isFalse);

    await platformReports(tester, AppLifecycleState.hidden);
    await platformReports(tester, AppLifecycleState.inactive);
    await platformReports(tester, AppLifecycleState.resumed);
    expect(container.read(appVisibleProvider), isTrue);
  });

  testWidgets('playback and the play history follow the room for as long as '
      'the app runs, with no page showing them', (tester) async {
    await pumpAlistenApp(tester);
    final container = appContainer(tester);

    expect(container.exists(playbackControllerProvider), isTrue);
    expect(container.exists(historyRecorderProvider), isTrue);
  });

  testWidgets('back in the foreground, the room connection and the '
      'notification permission are checked again', (tester) async {
    final rooms = FakeRoomTransportFactory();
    final notifications = FakeNotificationGateway();
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing()],
      credentials: FakeCredentialStore()..tickets['room-id'] = 'saved-ticket',
      rooms: rooms,
      notifications: notifications,
    );
    unawaited(
      appContainer(tester)
          .read(roomControllerProvider.notifier)
          .openRoom('listen'),
    );
    await tester.pump();
    rooms.last.emitHello();
    // 播放经过一次平台往返才开始。
    await tester.pump(const Duration(milliseconds: 1));
    await platformReports(tester, AppLifecycleState.paused);
    final probes = rooms.last.probeCalls;
    final permissionChecks = notifications.permissionChecks;

    await platformReports(tester, AppLifecycleState.resumed);

    expect(rooms.last.probeCalls, probes + 1);
    expect(notifications.permissionChecks, permissionChecks + 1);
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('back in the foreground after more than 5 minutes away, the '
      'site admin asks for the token again', (tester) async {
    var now = DateTime.utc(2026, 11, 2, 20);
    await pumpAlistenApp(
      tester,
      overrides: [adminNowProvider.overrideWithValue(() => now)],
    );
    final container = appContainer(tester);
    container.read(routerProvider).go('/settings/admin');
    await tester.pumpAndSettle();
    await container.read(adminSessionProvider.notifier).signIn('t-1');
    await tester.pumpAndSettle();
    expect(find.text('退出后台'), findsOneWidget);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      await platformReports(tester, state);
    }
    now = now.add(const Duration(minutes: 5, seconds: 1));
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      await platformReports(tester, state);
    }
    await tester.pumpAndSettle();

    expect(container.read(adminSessionProvider).active, isFalse);
    expect(find.text('进入后台'), findsOneWidget);
    expect(find.text(adminAwayText), findsOneWidget);
  });

  // 回到前台时，会话必须先于扫码面板结束，否则面板会用已超时的 token 立即查询
  // 一次：结果虽被丢弃，token 却已发出。
  testWidgets('back after more than 5 minutes away with a login code open, '
      'the session ends before the code is checked with its token', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 2, 20);
    final admin = FakeAdminApi()
      ..qrTicket = QrLoginTicket(
        key: 'k-1',
        qrImage: 'data:image/png;base64,iVBORw0KGgo=',
        expiresAtMs: now
            .add(const Duration(minutes: 30))
            .millisecondsSinceEpoch,
      );
    await pumpAlistenApp(
      tester,
      admin: admin,
      qrImages: FakeQrImageLoader()
        ..bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAA'
          'YAAjCB0C8AAAAASUVORK5CYII=',
        ),
      overrides: [adminNowProvider.overrideWithValue(() => now)],
    );
    final container = appContainer(tester);
    container.read(routerProvider).go('/settings/admin');
    await tester.pumpAndSettle();
    await container.read(adminSessionProvider.notifier).signIn('t-1');
    await tester.pumpAndSettle();
    final signIn = find.text('扫码登录').first;
    await tester.ensureVisible(signIn);
    await tester.pumpAndSettle();
    await tester.tap(signIn);
    await tester.pumpAndSettle();
    expect(find.text('等待扫码'), findsOneWidget);
    final tokens = admin.tokens.length;

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      await platformReports(tester, state);
    }
    now = now.add(const Duration(minutes: 6));
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      await platformReports(tester, state);
    }
    await tester.pumpAndSettle();

    expect(admin.checkCalls, 0);
    expect(admin.tokens, hasLength(tokens));
    expect(container.read(adminSessionProvider).active, isFalse);
    expect(find.text('等待扫码'), findsNothing);
    expect(find.text('进入后台'), findsOneWidget);
  });

  // 后台播放时进程一直在运行，不回前台也要按时结束会话。
  testWidgets('5 minutes in the background end the site admin session and '
      'close its sheets, without coming back', (tester) async {
    final admin = FakeAdminApi()
      ..qrTicket = QrLoginTicket(
        key: 'k-1',
        qrImage: 'data:image/png;base64,iVBORw0KGgo=',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 30))
            .millisecondsSinceEpoch,
      );
    await pumpAlistenApp(
      tester,
      admin: admin,
      qrImages: FakeQrImageLoader()
        ..bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAA'
          'YAAjCB0C8AAAAASUVORK5CYII=',
        ),
    );
    final container = appContainer(tester);
    container.read(routerProvider).go('/settings/admin');
    await tester.pumpAndSettle();
    await container.read(adminSessionProvider.notifier).signIn('t-1');
    await tester.pumpAndSettle();
    final signIn = find.text('扫码登录').first;
    await tester.ensureVisible(signIn);
    await tester.pumpAndSettle();
    await tester.tap(signIn);
    await tester.pumpAndSettle();
    final sheet = ModalRoute.of(tester.element(find.text('等待扫码')))!;
    final tokens = admin.tokens.length;

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      await platformReports(tester, state);
    }
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(container.read(adminSessionProvider).active, isTrue);

    await tester.pump(const Duration(seconds: 1));

    expect(container.read(adminSessionProvider).active, isFalse);
    expect(sheet.isActive, isFalse);
    expect(admin.tokens, hasLength(tokens));

    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      await platformReports(tester, state);
    }
    await tester.pumpAndSettle();

    expect(admin.tokens, hasLength(tokens));
    expect(find.text('等待扫码'), findsNothing);
    expect(find.text('进入后台'), findsOneWidget);
    expect(find.text(adminAwayText), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
  });

  // 回到前台时，其他跟随前台的逻辑可能立即发出请求。
  testWidgets('back in the foreground after 5 minutes away, the site admin '
      'session has ended before anything following the foreground '
      'runs', (tester) async {
    var now = DateTime.utc(2026, 11, 2, 20);
    await pumpAlistenApp(
      tester,
      overrides: [adminNowProvider.overrideWithValue(() => now)],
    );
    final container = appContainer(tester);
    await container.read(adminSessionProvider.notifier).signIn('t-1');
    final activeWhenVisible = <bool>[];
    container.listen(appVisibleProvider, (_, visible) {
      if (visible) {
        activeWhenVisible.add(container.read(adminSessionProvider).active);
      }
    });

    await platformReports(tester, AppLifecycleState.hidden);
    await platformReports(tester, AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 6));
    await platformReports(tester, AppLifecycleState.hidden);
    await platformReports(tester, AppLifecycleState.inactive);
    await platformReports(tester, AppLifecycleState.resumed);

    expect(activeWhenVisible, [false]);
  });
}
