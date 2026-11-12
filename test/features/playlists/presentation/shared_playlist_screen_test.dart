import 'dart:async';

import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playlists/application/shared_playlist_controller.dart';
import 'package:alisten/features/playlists/presentation/shared_playlist_screen.dart';
import 'package:alisten/features/search/application/pick_controller.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../playlists_page_harness.dart';
import '../playlists_test_doubles.dart';

void main() {
  late FakePlaylistApi server;
  late List<(ToastKind, String)> notices;
  late int accountOpened;

  setUp(() {
    notices = [];
    accountOpened = 0;
    server = FakePlaylistApi()
      ..sharedPlaylist = SharedPlaylist(
        name: '夜跑',
        favorites: false,
        ownerName: '阿柚',
        ownerAvatarHash: 'abc123',
        items: [
          song('a', coverUrl: ''),
          song('b', coverUrl: 'https://example.com/b.jpg'),
        ],
      );
  });

  Future<ProviderContainer> open(
    WidgetTester tester, {
    bool signedIn = true,
    Size size = const Size(360, 780),
    TextScaler textScaler = TextScaler.noScaling,
    List<Override> overrides = const [],
  }) {
    return pumpPlaylistsPage(
      tester,
      SharedPlaylistScreen(
        shareId: shareIdA,
        onResult: (_, _) {},
        onNotice: (kind, text) => notices.add((kind, text)),
        onCopyTitle: (_) {},
        onOpenAccount: () => accountOpened++,
      ),
      playlists: server,
      signedIn: signedIn,
      size: size,
      textScaler: textScaler,
      overrides: overrides,
    );
  }

  testWidgets('the header names the playlist and who shared it', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('夜跑'), findsOneWidget);
    expect(find.text('阿柚 分享，2 首'), findsOneWidget);
    final avatar = tester.widget<MemberAvatar>(find.byType(MemberAvatar));
    expect(avatar.name, '阿柚');
    expect(
      avatar.imageUrl,
      startsWith('https://www.gravatar.com/avatar/abc123'),
    );
    expect(find.text('复制到我的歌单'), findsOneWidget);
    expect(find.text('进入房间后可点歌'), findsOneWidget);
  });

  testWidgets('every song can be picked from its row and saved to a playlist '
      'from its menu', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    expect(find.bySemanticsLabel('点歌《歌a》'), findsOneWidget);
    expect(find.bySemanticsLabel('点歌《歌b》'), findsOneWidget);
    expect(find.bySemanticsLabel('《歌b》的更多操作'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('《歌a》的更多操作'));
    await settlePage(tester);
    expect(find.text('复制歌名'), findsOneWidget);
    await tester.tap(find.text('保存到歌单'));
    await settlePage(tester);

    expect(find.text('新建歌单'), findsOneWidget, reason: 'the save sheet');
    semantics.dispose();
  });

  testWidgets('a song without artist and album has no subtitle line', (
    tester,
  ) async {
    server.sharedPlaylist = SharedPlaylist(
      name: '夜跑',
      favorites: false,
      ownerName: '阿柚',
      ownerAvatarHash: '',
      items: [song('a', artist: '', album: '')],
    );
    await open(tester);

    final row = tester.widget<TrackRow>(
      find.ancestor(of: find.text('歌a'), matching: find.byType(TrackRow)),
    );
    expect(row.subtitle, isNull);
  });

  testWidgets('a share that is gone says so', (tester) async {
    server.sharedPlaylist = null;
    await open(tester);

    expect(find.text('分享已失效'), findsOneWidget);
    expect(find.text('歌单被删除了，或者分享的人停止了分享。'), findsOneWidget);
    expect(find.byIcon(AlistenIcons.linkBreak), findsOneWidget);
  });

  testWidgets('an empty share says so', (tester) async {
    server.sharedPlaylist = const SharedPlaylist(
      name: '空的',
      favorites: false,
      ownerName: '阿柚',
      ownerAvatarHash: '',
      items: [],
    );
    await open(tester);

    expect(find.text('这个歌单还是空的'), findsOneWidget);
  });

  testWidgets('an empty share keeps clear of the mini player', (tester) async {
    server.sharedPlaylist = const SharedPlaylist(
      name: '空的',
      favorites: false,
      ownerName: '阿柚',
      ownerAvatarHash: '',
      items: [],
    );
    await pumpPlaylistsPage(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(padding: const EdgeInsets.only(bottom: 120)),
          child: SharedPlaylistScreen(
            shareId: shareIdA,
            onResult: (_, _) {},
            onNotice: (kind, text) => notices.add((kind, text)),
            onCopyTitle: (_) {},
            onOpenAccount: () {},
          ),
        ),
      ),
      playlists: server,
    );

    expect(
      tester.getRect(find.byType(EmptyState)).bottom,
      lessThanOrEqualTo(780 - 120),
    );
  });

  testWidgets('a failed read offers a retry', (tester) async {
    server.failNext('shared', networkError);
    await open(tester);

    expect(find.text('读取失败：${networkError.message}'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await settlePage(tester);
    expect(find.text('阿柚 分享，2 首'), findsOneWidget);
  });

  testWidgets('a guest who wants a copy is asked to sign in', (tester) async {
    await open(tester, signedIn: false);

    await tester.tap(find.text('复制到我的歌单'));
    await settlePage(tester);

    expect(find.text('注册或登录之后就能把这个歌单复制到自己的歌单。'), findsOneWidget);
    await tester.tap(find.text('去账号设置'));
    await settlePage(tester);
    expect(accountOpened, 1);
    expect(
      server.calls.where((call) => call.startsWith('copyShared')),
      isEmpty,
    );
  });

  testWidgets('a guest who registers keeps the copy sheet open', (
    tester,
  ) async {
    final container = await open(tester, signedIn: false);
    await tester.tap(find.text('复制到我的歌单'));
    await settlePage(tester);
    expect(find.text('注册或登录之后就能把这个歌单复制到自己的歌单。'), findsOneWidget);

    final identity = container.read(identityControllerProvider);
    container
        .read(identityControllerProvider.notifier)
        .updateAccount(identity.member!.id, testAccount);
    await settlePage(tester);

    expect(find.text('注册或登录之后就能把这个歌单复制到自己的歌单。'), findsNothing);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '夜跑',
    );
  });

  testWidgets('a copy takes the shared name and tells how many songs', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('复制到我的歌单'));
    await settlePage(tester);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '夜跑',
    );
    await tester.tap(find.widgetWithText(PillButton, '复制'));
    await settlePage(tester);

    expect(server.calls, contains('copyShared $shareIdA 夜跑'));
    expect(notices, [(ToastKind.success, '已复制为“夜跑”，共 2 首')]);
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('a copy that answers under another sheet closes only its own '
      'sheet and tells it', (tester) async {
    await open(tester);
    await tester.tap(find.text('复制到我的歌单'));
    await settlePage(tester);
    final answer = server.hold('copyShared');
    await tester.tap(find.widgetWithText(PillButton, '复制'));
    await tester.pump();
    unawaited(
      showSheetPanel<void>(
        tester.element(find.byType(EditableText)),
        builder: (_) => const Text('盖在上面'),
      ),
    );
    await settlePage(tester);

    answer.complete();
    await settlePage(tester);

    expect(find.text('盖在上面'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(notices, [(ToastKind.success, '已复制为“夜跑”，共 2 首')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a copy of a share that has just gone tells the server '
      'message and turns the page into the expired one', (tester) async {
    await open(tester);
    server
      ..onCall = (method) {
        if (method == 'copyShared') server.sharedPlaylist = null;
      }
      ..failNext(
        'copyShared',
        apiError('NOT_FOUND', message: '分享已经停止了', status: 404),
      );

    await tester.tap(find.text('复制到我的歌单'));
    await settlePage(tester);
    await tester.tap(find.widgetWithText(PillButton, '复制'));
    await settlePage(tester);
    expect(find.text('分享已经停止了'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await settlePage(tester);
    expect(find.text('分享已失效'), findsOneWidget);
  });

  testWidgets('the sheet still copies once the page under it is gone', (
    tester,
  ) async {
    final showing = ValueNotifier(true);
    addTearDown(showing.dispose);
    final container = await pumpPlaylistsPage(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: showing,
        builder: (_, shown, _) => shown
            ? SharedPlaylistScreen(
                shareId: shareIdA,
                onResult: (_, _) {},
                onNotice: (kind, text) => notices.add((kind, text)),
                onCopyTitle: (_) {},
                onOpenAccount: () {},
              )
            : const SizedBox(),
      ),
      playlists: server,
    );
    await tester.tap(find.text('复制到我的歌单'));
    await settlePage(tester);

    showing.value = false;
    await settlePage(tester);
    expect(find.text('夜跑'), findsOneWidget);
    await tester.tap(find.widgetWithText(PillButton, '复制'));
    await settlePage(tester);

    expect(tester.takeException(), isNull);
    expect(server.calls, contains('copyShared $shareIdA 夜跑'));
    expect(notices, [(ToastKind.success, '已复制为“夜跑”，共 2 首')]);
    expect(find.byType(EditableText), findsNothing);
    expect(
      container.exists(sharedPlaylistControllerProvider(shareIdA)),
      isFalse,
    );
  });

  testWidgets('the sheet shows the server message for a share that has gone '
      'once the page under it is gone, and reads nothing again', (
    tester,
  ) async {
    final showing = ValueNotifier(true);
    addTearDown(showing.dispose);
    final container = await pumpPlaylistsPage(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: showing,
        builder: (_, shown, _) => shown
            ? SharedPlaylistScreen(
                shareId: shareIdA,
                onResult: (_, _) {},
                onNotice: (kind, text) => notices.add((kind, text)),
                onCopyTitle: (_) {},
                onOpenAccount: () {},
              )
            : const SizedBox(),
      ),
      playlists: server,
    );
    await tester.tap(find.text('复制到我的歌单'));
    await settlePage(tester);
    showing.value = false;
    await settlePage(tester);
    final reads = server.calls
        .where((call) => call.startsWith('shared'))
        .length;
    server.failNext(
      'copyShared',
      apiError('NOT_FOUND', message: '分享已经停止了', status: 404),
    );
    await tester.tap(find.widgetWithText(PillButton, '复制'));
    await settlePage(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('分享已经停止了'), findsOneWidget);
    expect(
      server.calls.where((call) => call.startsWith('shared')).length,
      reads,
    );
    // 复制经过分享页的控制器，面板开着时由它让控制器活着。
    expect(
      container.exists(sharedPlaylistControllerProvider(shareIdA)),
      isTrue,
    );

    await tester.tap(find.text('取消'));
    await settlePage(tester);
    expect(
      container.exists(sharedPlaylistControllerProvider(shareIdA)),
      isFalse,
    );
  });

  for (final scale in [2.0, 3.0]) {
    testWidgets('at 320 dp and ${scale}x text an unknown pick result fits '
        'beside the menu', (tester) async {
      await open(
        tester,
        size: const Size(320, 760),
        textScaler: TextScaler.linear(scale),
        overrides: [
          pickControllerProvider.overrideWithBuild(
            (ref, _) => Picks(
              statuses: {trackKey(song('a').track): PickStatus.unknown},
            ),
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(find.text('结果未知'), findsOneWidget);
      await tester.ensureVisible(find.text('结果未知'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byIcon(AlistenIcons.dotsThreeBold).hitTestable(),
        findsWidgets,
      );
      expect(
        find.byIcon(AlistenIcons.questionBold).hitTestable(),
        findsWidgets,
      );
    });
  }
}
