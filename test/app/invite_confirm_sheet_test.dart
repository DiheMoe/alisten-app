import 'dart:async';
import 'dart:convert';

import 'package:alisten/app/router.dart';
import 'package:alisten/domain/server/invite_link.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/features/server/data/preferences_server_store.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../features/playlists/playlists_test_doubles.dart';
import '../features/server/server_test_doubles.dart'
    show FakeCredentialStores, FakeServerProbe, serverB;
import 'app_test_harness.dart';

final _newSite = ServerProfile(
  origin: 'https://new.example.org',
  brandName: '新站',
  addedAtMs: 3,
);

InviteLink _link(String link) => parseInviteLink(link, allowCleartext: false)!;

final _toB = InviteToSaved(
  link: _link('https://example.com:8443/r/abc'),
  server: serverB,
);

final _toNewSite = InviteToNew(
  link: _link('https://new.example.org/r/party'),
  server: _newSite,
);

final _toListen = InviteToCurrent(
  link: _link('https://livehouse.dihe.moe/r/listen'),
  isActiveRoom: false,
);

const _shareId = 'AbCdEfGhIjKlMnOpQrStUv';

final _playlistOnB = InviteToSaved(
  link: _link('https://example.com:8443/s/$_shareId'),
  server: serverB,
);

final _playlistOnNewSite = InviteToNew(
  link: _link('https://new.example.org/s/$_shareId'),
  server: _newSite,
);

void main() {
  late FakeServerProbe probe;
  late FakeAppLinkSource links;
  late FakePlaylistApi playlists;

  setUp(() {
    probe = FakeServerProbe();
    links = FakeAppLinkSource();
    playlists = FakePlaylistApi();
  });

  /// 默认服务器为当前服务器，另已保存并加入过 [serverB]；给出 [current] 时以它
  /// 为当前服务器。
  Future<void> open(
    WidgetTester tester, {
    String? current,
    MediaQueryData system = const MediaQueryData(),
    Override? playlistApi,
  }) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final credentials = FakeCredentialStores();
    credentials(serverB.id).memberToken = 'b';
    await pumpAlistenApp(
      tester,
      system: system,
      credentialStores: credentials,
      probe: probe,
      links: links,
      playlists: playlists,
      preferences: {
        PreferencesServerStore.profilesKey: jsonEncode([serverB.toJson()]),
        PreferencesServerStore.currentKey: ?current,
      },
      playlistApi: playlistApi,
    );
  }

  ProviderContainer app(WidgetTester tester) => appContainer(tester);

  GoRouter router(WidgetTester tester) => app(tester).read(routerProvider);

  String currentId(WidgetTester tester) =>
      app(tester).read(currentServerProvider).id;

  Future<void> offer(WidgetTester tester, InviteTarget target) async {
    app(tester).read(inviteOfferControllerProvider.notifier).offer(target);
    await tester.pumpAndSettle();
  }

  // 房间页的背景动画不会停止，进入房间后只能逐步推进时间。
  Future<void> settleInRoom(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  // 读取挂起时分享页一直在转圈，pumpAndSettle 等不到结束，只能逐步推进时间。
  Future<void> settleWhileReading(WidgetTester tester) async {
    for (var step = 0; step < 20; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 记下读取分享时的当前服务器。
  List<String> sharesReadOn(WidgetTester tester) {
    final servers = <String>[];
    playlists.onCall = (method) {
      if (method == 'shared') servers.add(currentId(tester));
    };
    return servers;
  }

  testWidgets('a room on the current server is opened without asking', (
    tester,
  ) async {
    await open(tester);

    app(tester).read(inviteOfferControllerProvider.notifier).offer(_toListen);
    await settleInRoom(tester);

    expect(find.byType(ConfirmSheet), findsNothing);
    expect(router(tester).state.uri.path, '/r/listen');
    expect(app(tester).read(inviteOfferControllerProvider), isNull);
  });

  testWidgets('a room on a saved server is entered once switching there is '
      'confirmed', (tester) async {
    await open(tester);

    await offer(tester, _toB);

    expect(find.text('切换到 周末听歌会 并进入房间？'), findsOneWidget);
    expect(find.text('服务器：example.com:8443。切换后会退出当前房间。'), findsOneWidget);
    await tester.tap(find.text('切换并进入'));
    await settleInRoom(tester);

    expect(currentId(tester), serverB.id);
    expect(router(tester).state.uri.path, '/r/abc');
    expect(app(tester).read(inviteOfferControllerProvider), isNull);
  });

  testWidgets('a room on a saved server not confirmed changes nothing', (
    tester,
  ) async {
    await open(tester);

    await offer(tester, _toB);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(ConfirmSheet), findsNothing);
    expect(currentId(tester), isNot(serverB.id));
    expect(router(tester).state.uri.path, '/');
    expect(app(tester).read(inviteOfferControllerProvider), isNull);
  });

  testWidgets('a room on a new server is entered once it is added, its '
      'version checked and joined', (tester) async {
    await open(tester);

    await offer(tester, _toNewSite);

    expect(find.text('添加 新站 并进入房间？'), findsOneWidget);
    expect(
      find.text('服务器：new.example.org。添加后会切换到这个服务器，并退出当前房间。'),
      findsOneWidget,
    );
    expect(probe.handshakes, isEmpty);
    await tester.tap(find.text('添加并进入'));
    await tester.pumpAndSettle();

    expect(probe.handshakes, ['https://new.example.org']);
    expect(find.text('加入 新站'), findsOneWidget);
    await tester.tap(find.text('加入'));
    await settleInRoom(tester);

    final directory = app(tester).read(serverDirectoryProvider);
    expect(directory.byId(_newSite.id)?.brandName, '新站');
    expect(currentId(tester), _newSite.id);
    expect(router(tester).state.uri.path, '/r/party');
  });

  testWidgets('a new server not joined is not added', (tester) async {
    await open(tester);
    final before = currentId(tester);

    await offer(tester, _toNewSite);
    await tester.tap(find.text('添加并进入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('加入 新站'), findsNothing);
    expect(app(tester).read(serverDirectoryProvider).byId(_newSite.id), isNull);
    expect(currentId(tester), before);
    expect(router(tester).state.uri.path, '/');
  });

  testWidgets('a new server of another version says so and is not added', (
    tester,
  ) async {
    probe.handshakeFailures['https://new.example.org'] =
        ProbeFailure.incompatible;
    await open(tester);
    final before = currentId(tester);

    await offer(tester, _toNewSite);
    await tester.tap(find.text('添加并进入'));
    await tester.pumpAndSettle();

    expect(find.text('这个服务器与当前 App 版本不兼容'), findsOneWidget);
    expect(find.text('加入 新站'), findsNothing);
    expect(app(tester).read(serverDirectoryProvider).byId(_newSite.id), isNull);
    expect(currentId(tester), before);
    expect(router(tester).state.uri.path, '/');
  });

  testWidgets('an invite arriving while another is asked about follows once '
      'that one is answered', (tester) async {
    await open(tester);

    await offer(tester, _toB);
    await offer(tester, _toListen);
    expect(router(tester).state.uri.path, '/');
    expect(find.text('切换到 周末听歌会 并进入房间？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    for (var step = 0; step < 3; step++) {
      await settleInRoom(tester);
    }

    expect(router(tester).state.uri.path, '/r/listen');
    expect(currentId(tester), isNot(serverB.id));
  });

  testWidgets('an invite waiting while the server is switched is told again '
      'on the new server: a room of the server left asks to switch back', (
    tester,
  ) async {
    await open(tester);

    await offer(tester, _toB);
    await offer(tester, _toListen);
    await tester.tap(find.text('切换并进入'));
    for (var step = 0; step < 3; step++) {
      await settleInRoom(tester);
    }

    expect(currentId(tester), serverB.id);
    expect(router(tester).state.uri.path, '/r/abc');
    expect(find.text('切换到 Alisten 并进入房间？'), findsOneWidget);
    expect(find.text('服务器：livehouse.dihe.moe。切换后会退出当前房间。'), findsOneWidget);
  });

  testWidgets('the version of a new server is checked with the sheet still '
      'up, busy, and not checked twice', (tester) async {
    await open(tester, system: const MediaQueryData(disableAnimations: true));
    probe.gate = Completer();

    await offer(tester, _toNewSite);
    await tester.tap(find.text('添加并进入'));
    await tester.pump();
    await tester.pump();

    expect(probe.handshakes, ['https://new.example.org']);
    expect(find.text('添加 新站 并进入房间？'), findsOneWidget);
    expect(find.text('正在检查服务器…'), findsOneWidget);
    expect(
      tester
          .widget<PillButton>(find.widgetWithText(PillButton, '正在检查服务器…'))
          .busy,
      isTrue,
    );
    expect(tester.hasRunningAnimations, isFalse);

    await tester.tap(find.text('正在检查服务器…'), warnIfMissed: false);
    await tester.pump();
    expect(probe.handshakes, hasLength(1));

    probe.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('添加 新站 并进入房间？'), findsNothing);
    expect(find.text('加入 新站'), findsOneWidget);
  });

  testWidgets('a version check ending while the cancelled sheet closes leaves '
      'the page under the sheet as it is', (tester) async {
    await open(tester);
    router(tester).go('/settings');
    await tester.pumpAndSettle();
    probe.gate = Completer();

    await offer(tester, _toNewSite);
    await tester.tap(find.text('添加并进入'));
    await tester.pump();
    expect(find.text('正在检查服务器…'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    probe.gate!.complete();
    await tester.pumpAndSettle();

    expect(router(tester).state.uri.path, '/settings');
    expect(find.byType(ConfirmSheet), findsNothing);
    expect(find.text('加入 新站'), findsNothing);
    expect(app(tester).read(serverDirectoryProvider).byId(_newSite.id), isNull);
  });

  testWidgets('cancelling while the version is checked stops the check', (
    tester,
  ) async {
    await open(tester);
    probe.gate = Completer();

    await offer(tester, _toNewSite);
    await tester.tap(find.text('添加并进入'));
    await tester.pump();
    var stopped = false;
    unawaited(probe.handshakeCancels.single!.then((_) => stopped = true));
    await tester.pump();
    expect(stopped, isFalse);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(stopped, isTrue, reason: 'the handshake is stopped, not waited out');

    probe.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('加入 新站'), findsNothing);
    expect(app(tester).read(serverDirectoryProvider).byId(_newSite.id), isNull);
    expect(router(tester).state.uri.path, '/');
  });

  testWidgets('an invite arriving just as a waiting one is taken up is '
      'asked about alone', (tester) async {
    await open(tester);
    final third = InviteToNew(
      link: _link('https://third.example.org/r/x'),
      server: ServerProfile(
        origin: 'https://third.example.org',
        brandName: '第三站',
        addedAtMs: 4,
      ),
    );

    await offer(tester, _toB);
    await offer(tester, _toNewSite);
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    app(tester).read(inviteOfferControllerProvider.notifier).offer(third);
    await tester.pumpAndSettle();

    expect(find.byType(ConfirmSheet), findsOneWidget);
    expect(find.text('添加 第三站 并进入房间？'), findsOneWidget);
    expect(find.text('添加 新站 并进入房间？'), findsNothing);
  });

  testWidgets('a shared playlist on a saved server is opened, and read, '
      'once switching there is confirmed', (tester) async {
    await open(tester);
    final readOn = sharesReadOn(tester);

    await offer(tester, _playlistOnB);

    expect(find.text('切换到 周末听歌会 并打开歌单？'), findsOneWidget);
    expect(find.text('服务器：example.com:8443。切换后会退出当前房间。'), findsOneWidget);
    expect(playlists.count('shared'), 0);
    final reading = playlists.hold('shared');
    await tester.tap(find.text('切换并打开'));
    await settleWhileReading(tester);

    expect(readOn, [serverB.id]);
    expect(currentId(tester), serverB.id);
    reading.complete();
    await tester.pumpAndSettle();

    expect(currentId(tester), serverB.id);
    expect(router(tester).state.uri.path, '/s/$_shareId');
  });

  testWidgets('a shared playlist left open while switching to another '
      'server for its own is never asked of the new server', (tester) async {
    final onB = FakePlaylistApi()
      ..sharedPlaylist = SharedPlaylist(
        name: '别处',
        favorites: false,
        ownerName: '阿柚',
        ownerAvatarHash: '',
        items: [song('b')],
      );
    playlists.sharedPlaylist = SharedPlaylist(
      name: '夜跑',
      favorites: false,
      ownerName: '阿柚',
      ownerAvatarHash: '',
      items: [song('a')],
    );
    await open(
      tester,
      playlistApi: playlistApiProvider.overrideWith(
        (ref) =>
            ref.watch(currentServerProvider).id == serverB.id ? onB : playlists,
      ),
    );
    router(tester).go('/s/$shareIdA');
    await tester.pumpAndSettle();
    expect(playlists.calls, ['shared $shareIdA']);

    await offer(
      tester,
      InviteToSaved(
        link: _link('https://example.com:8443/s/$shareIdB'),
        server: serverB,
      ),
    );
    await tester.tap(find.text('切换并打开'));
    await tester.pumpAndSettle();

    expect(currentId(tester), serverB.id);
    expect(router(tester).state.uri.path, '/s/$shareIdB');
    expect(onB.calls, ['shared $shareIdB']);
    expect(playlists.calls, ['shared $shareIdA']);
  });

  testWidgets('a shared playlist on a saved server not confirmed changes '
      'nothing', (tester) async {
    await open(tester);

    await offer(tester, _playlistOnB);
    expect(find.text('切换到 周末听歌会 并打开歌单？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(ConfirmSheet), findsNothing);
    expect(currentId(tester), isNot(serverB.id));
    expect(router(tester).state.uri.path, '/');
  });

  testWidgets('a shared playlist on a new server is opened, and read, once '
      'the server is added and joined', (tester) async {
    await open(tester);
    final readOn = sharesReadOn(tester);

    await offer(tester, _playlistOnNewSite);

    expect(find.text('添加 新站 并打开歌单？'), findsOneWidget);
    expect(
      find.text('服务器：new.example.org。添加后会切换到这个服务器，并退出当前房间。'),
      findsOneWidget,
    );
    await tester.tap(find.text('添加并打开'));
    await tester.pumpAndSettle();
    expect(playlists.count('shared'), 0);
    final reading = playlists.hold('shared');
    await tester.tap(find.text('加入'));
    await settleWhileReading(tester);

    expect(readOn, [_newSite.id]);
    expect(currentId(tester), _newSite.id);
    reading.complete();
    await tester.pumpAndSettle();

    expect(currentId(tester), _newSite.id);
    expect(router(tester).state.uri.path, '/s/$_shareId');
  });

  testWidgets('a shared playlist on the current server is opened without '
      'asking', (tester) async {
    await open(tester);

    await offer(
      tester,
      InviteToCurrent(
        link: _link('https://livehouse.dihe.moe/s/$_shareId'),
        isActiveRoom: false,
      ),
    );

    expect(find.byType(ConfirmSheet), findsNothing);
    expect(router(tester).state.uri.path, '/s/$_shareId');
  });

  testWidgets('an app link to a shared playlist of another server asks to '
      'switch there first and reads nothing from this server', (tester) async {
    await open(tester, current: serverB.id);

    links.open(Uri.parse('https://livehouse.dihe.moe/s/$_shareId'));
    await tester.pumpAndSettle();

    expect(find.text('切换到 Alisten 并打开歌单？'), findsOneWidget);
    expect(find.text('服务器：livehouse.dihe.moe。切换后会退出当前房间。'), findsOneWidget);
    expect(find.text('切换并打开'), findsOneWidget);
    expect(probe.siteProbed, isEmpty);
    expect(playlists.count('shared'), 0);
    expect(router(tester).state.uri.path, '/');
  });

  group('an app link to a room of another server', () {
    testWidgets('is offered as an invite', (tester) async {
      await open(tester, current: serverB.id);

      links.open(Uri.parse('https://livehouse.dihe.moe/r/listen'));
      await tester.pumpAndSettle();

      expect(find.text('切换到 Alisten 并进入房间？'), findsOneWidget);
      expect(find.text('服务器：livehouse.dihe.moe。切换后会退出当前房间。'), findsOneWidget);
      expect(probe.siteProbed, isEmpty);
    });

    testWidgets('on a website that is not Alisten is an invalid link', (
      tester,
    ) async {
      await open(tester);
      router(tester).go('/settings');
      await tester.pumpAndSettle();

      links.open(Uri.parse('https://www.reddit.com/r/flutterdev'));
      await tester.pumpAndSettle();

      expect(probe.siteProbed, [
        ('https://www.reddit.com', const Duration(seconds: 5)),
      ]);
      expect(find.byType(ConfirmSheet), findsNothing);
      expect(find.text(invalidLinkText), findsOneWidget);
      expect(router(tester).state.uri.path, '/');
    });
  });
}
