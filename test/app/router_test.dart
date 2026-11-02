import 'dart:convert';

import 'package:alisten/app/router.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:alisten/features/lobby/index.dart';
import 'package:alisten/features/server/data/preferences_server_store.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/admin/admin_test_doubles.dart';
import '../features/lobby/lobby_test_doubles.dart';
import '../features/server/server_test_doubles.dart'
    show FakeCredentialStores, serverB;
import 'app_test_harness.dart';

void main() {
  testWidgets('a page left by a navigation it did not start, such as a link, '
      'does not take the keyboard back on return', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()
        ..rooms = [roomListing(id: testRoomId, slug: 'listen')],
      credentials: FakeCredentialStore()..tickets[testRoomId] = 'saved-ticket',
    );
    final router = appContainer(tester).read(routerProvider);
    final filter = find.descendant(
      of: find.byType(LobbyScreen),
      matching: find.byType(EditableText),
    );
    // 房间页的背景动画不会停止，只能逐步推进时间。
    Future<void> settle() async {
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is IconCircleButton && widget.semanticLabel == '筛选房间',
      ),
    );
    await settle();
    await tester.enterText(filter, '一起');
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    for (final away in ['/r/listen', '/settings']) {
      router.go(away);
      await settle();
      router.go('/');
      await settle();

      expect(find.byType(LobbyScreen), findsOneWidget, reason: away);
      expect(tester.testTextInput.isVisible, isFalse, reason: away);
      expect(
        tester.widget<EditableText>(filter).focusNode.hasFocus,
        isFalse,
        reason: away,
      );
      expect(tester.widget<EditableText>(filter).controller.text, '一起');
      await tester.tap(filter);
      await settle();
      expect(tester.testTextInput.isVisible, isTrue, reason: away);
    }
  });

  testWidgets('a card focused from a keyboard keeps its focus through a trip '
      'to its room and back', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()
        ..rooms = [roomListing(id: testRoomId, slug: 'listen')],
      credentials: FakeCredentialStore()..tickets[testRoomId] = 'saved-ticket',
    );
    final router = appContainer(tester).read(routerProvider);
    // 房间页的背景动画不会停止，只能逐步推进时间。
    Future<void> settle() async {
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    final card = Focus.of(tester.element(find.text('一起听')));
    card.requestFocus();
    await settle();
    expect(card.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle();
    expect(router.state.uri.path, '/r/listen');

    router.go('/');
    await settle();
    expect(card.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('the servers have a page under the settings', (tester) async {
    await pumpAlistenApp(tester);
    final router = appContainer(tester).read(routerProvider);

    router.go('/settings/servers');
    await tester.pump();
    await tester.pump();

    expect(router.state.uri.path, '/settings/servers');
    expect(find.text(invalidLinkText), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(ServerScreen), findsOneWidget);
    expect(find.text(invalidLinkText), findsNothing);
  });

  testWidgets('the rhythm on the version row opens the servers, and a server '
      'switched to there leads back to the lobby', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final credentials = FakeCredentialStores();
    credentials(serverB.id).memberToken = 'b';
    await pumpAlistenApp(
      tester,
      credentialStores: credentials,
      preferences: {
        PreferencesServerStore.profilesKey: jsonEncode([serverB.toJson()]),
      },
    );
    final router = appContainer(tester).read(routerProvider);
    router.go('/settings');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('版本'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    for (final long in [true, true, false, true, true, false]) {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('版本')),
      );
      await tester.pump(Duration(milliseconds: long ? 500 : 100));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/settings/servers');
    expect(find.byType(ServerScreen), findsOneWidget);

    await tester.tap(find.text('周末听歌会'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/');
    expect(find.byType(LobbyScreen), findsOneWidget);
    expect(appContainer(tester).read(currentServerProvider).id, serverB.id);
    expect(find.text('已切换到 周末听歌会'), findsOneWidget);
  });

  group('the site admin', () {
    final tokenField = find.descendant(
      of: find.widgetWithText(AlistenTextField, '管理 token'),
      matching: find.byType(EditableText),
    );

    Future<void> signIn(WidgetTester tester) async {
      await tester.enterText(tokenField, 't-1');
      await tester.tap(find.text('进入后台'));
      await tester.pumpAndSettle();
      expect(find.text('退出后台'), findsOneWidget);
    }

    bool active(WidgetTester tester) =>
        appContainer(tester).read(adminSessionProvider).active;

    Future<void> systemBack() {
      return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            SystemChannels.navigation.name,
            const JSONMessageCodec().encodeMessage(<String, Object?>{
              'method': 'popRoute',
            }),
            (_) {},
          );
    }

    testWidgets('has a page under the settings, and the session ends once '
        'the page is left', (tester) async {
      final admin = FakeAdminApi();
      await pumpAlistenApp(tester, admin: admin);
      final router = appContainer(tester).read(routerProvider);

      router.go('/settings/admin');
      await tester.pump();
      await tester.pump();
      expect(router.state.uri.path, '/settings/admin');
      expect(find.text(invalidLinkText), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(AdminScreen), findsOneWidget);
      expect(find.text('进入后台'), findsOneWidget);

      await signIn(tester);
      // 验证 token 和后台首页各读一次常驻房间列表，各音源账号各读一次，YouTube
      // Cookie 状态读一次；读取品牌名不带 token。
      expect(admin.listRoomsCalls, 2);
      expect(admin.sourceAccountCalls, unorderedEquals(LoginSource.values));
      expect(admin.getYoutubeCookieCalls, 1);
      expect(admin.tokens, List.filled(6, 't-1'));
      expect(active(tester), isTrue);

      router.go('/settings');
      await tester.pumpAndSettle();

      expect(active(tester), isFalse);
      expect(find.byType(AdminScreen), findsNothing);

      router.go('/settings/admin');
      await tester.pumpAndSettle();
      expect(find.text('进入后台'), findsOneWidget);
    });

    testWidgets('is left for the settings by its button or by going back, '
        'ending the session either way', (tester) async {
      await pumpAlistenApp(tester);
      final router = appContainer(tester).read(routerProvider);
      router.go('/settings');
      await tester.pumpAndSettle();
      router.go('/settings/admin');
      await tester.pumpAndSettle();

      await signIn(tester);
      await tester.tap(find.text('退出后台'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/settings');
      expect(active(tester), isFalse);

      router.go('/settings/admin');
      await tester.pumpAndSettle();
      await signIn(tester);
      await systemBack();
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/settings');
      expect(find.byType(AdminScreen), findsNothing);
      expect(active(tester), isFalse);
    });

    testWidgets('enters a room by its alias, leaving the site admin and ending '
        'the session', (tester) async {
      final room = roomListing(id: testRoomId, slug: 'listen');
      await pumpAlistenApp(
        tester,
        api: FakeAlistenApi()..rooms = [room],
        credentials: FakeCredentialStore()
          ..tickets[testRoomId] = 'saved-ticket',
        admin: FakeAdminApi()..rooms = [room],
      );
      final router = appContainer(tester).read(routerProvider);
      router.go('/settings/admin');
      await tester.pumpAndSettle();
      await signIn(tester);

      await tester.tap(find.text('一起听'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('进入'));
      // 房间页的背景动画不会停止，只能逐步推进时间。
      for (var step = 0; step < 3; step++) {
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }

      expect(router.state.uri.path, '/r/listen');
      expect(find.byType(AdminScreen), findsNothing);
      expect(active(tester), isFalse);
    });

    testWidgets('copies a new API key through the sensitive clipboard', (
      tester,
    ) async {
      final sensitive = FakeSensitiveClipboard();
      await pumpAlistenApp(
        tester,
        admin: FakeAdminApi()..rooms = [roomListing(id: testRoomId)],
        sensitiveClipboard: sensitive,
      );
      final router = appContainer(tester).read(routerProvider);
      router.go('/settings/admin');
      await tester.pumpAndSettle();
      await signIn(tester);

      await tester.tap(find.text('一起听'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('API Key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重置 API Key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();

      expect(sensitive.copied, ['k-new']);
      expect(find.text('API Key 已复制'), findsOneWidget);
    });

    testWidgets('saves a login code through the gallery', (tester) async {
      final qrImages = FakeQrImageLoader()
        ..bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAA'
          'YAAjCB0C8AAAAASUVORK5CYII=',
        );
      final gallery = FakeImageGallery();
      await pumpAlistenApp(
        tester,
        qrImages: qrImages,
        gallery: gallery,
        // 假接口返回的二维码在此时刻 2 分钟后过期。
        overrides: [
          adminNowProvider.overrideWithValue(
            () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
          ),
        ],
      );
      final router = appContainer(tester).read(routerProvider);
      router.go('/settings/admin');
      await tester.pumpAndSettle();
      await signIn(tester);

      final netease = find.text('扫码登录').first;
      await tester.ensureVisible(netease);
      await tester.pumpAndSettle();
      await tester.tap(netease);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存到相册'));
      await tester.pumpAndSettle();

      expect(qrImages.loaded, hasLength(1));
      expect(gallery.saved.single.name, 'alisten-netease-login');
      expect(find.text('已保存到相册'), findsOneWidget);
    });

    testWidgets('opens from the fate motif and a hold on the version row', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(360, 780) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpAlistenApp(tester);
      final router = appContainer(tester).read(routerProvider);
      router.go('/settings');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('版本'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final row = tester.getCenter(find.text('版本'));

      for (final long in [
        false,
        false,
        false,
        true,
        false,
        false,
        false,
        true,
      ]) {
        final gesture = await tester.startGesture(row);
        await tester.pump(Duration(milliseconds: long ? 500 : 100));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 200));
      }
      final hold = await tester.startGesture(row);
      await tester.pump(const Duration(seconds: 2));
      await hold.up();
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/settings/admin');
      expect(find.byType(AdminScreen), findsOneWidget);
    });
  });

  testWidgets('a location the app has no page for leads to the lobby and '
      'says so', (tester) async {
    await pumpAlistenApp(tester);
    final router = appContainer(tester).read(routerProvider);

    for (final location in [
      '/r/x/foo',
      // 只有网易云有歌单页。
      '/r/x/playlists/qq/1',
      '/r/Not_A_Room',
    ]) {
      router.go('/settings');
      await tester.pumpAndSettle();
      router.go(location);
      await tester.pump();
      await tester.pump();

      expect(router.state.uri.path, '/', reason: location);
      expect(find.text('链接无效，已回到大厅'), findsOneWidget, reason: location);
      await tester.pumpAndSettle();
      expect(find.text(emptyLobbyText), findsOneWidget, reason: location);
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(find.text('链接无效，已回到大厅'), findsNothing);
    }
  });
}
