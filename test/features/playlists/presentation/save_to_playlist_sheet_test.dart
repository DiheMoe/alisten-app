import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/presentation/playlist_states.dart';
import 'package:alisten/features/playlists/presentation/save_to_playlist_sheet.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playlists_page_harness.dart';
import '../playlists_test_doubles.dart';

const _song = Track(source: TrackSource.netease, id: 'a');

void main() {
  late FakePlaylistApi server;
  late List<(ToastKind, String)> notices;
  late int accountOpened;

  setUp(() {
    notices = [];
    accountOpened = 0;
    server = FakePlaylistApi()
      ..playlists.addAll([
        playlist('fav', name: '我喜欢', favorites: true, updatedAtMs: 1),
        playlist('pl-1', name: '夜跑', updatedAtMs: 5),
        playlist('pl-2', name: '晨跑', updatedAtMs: 9),
      ])
      ..contents['fav'] = []
      ..contents['pl-1'] = []
      ..contents['pl-2'] = [song('a')];
  });

  Widget host(SaveTarget? many) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => many == null
              ? SaveToPlaylistButton(
                  track: _song,
                  title: '晴天',
                  onOpenAccount: () => accountOpened++,
                  onNotice: (kind, text) => notices.add((kind, text)),
                )
              : TextButton(
                  onPressed: () => unawaited(
                    showSaveToPlaylistSheet(
                      context,
                      many,
                      onOpenAccount: () => accountOpened++,
                      onNotice: (kind, text) => notices.add((kind, text)),
                    ),
                  ),
                  child: const Text('保存选中的歌'),
                ),
        ),
      ),
    );
  }

  final several = SaveManyTracks(
    from: playlist('pl-1', name: '夜跑'),
    tracks: const [
      _song,
      Track(source: TrackSource.qq, id: 'b'),
    ],
  );

  /// [restored] 时身份在打开面板之前就已读到，与 App 启动之后相同；否则在面板
  /// 打开期间才读到。
  Future<ProviderContainer> pumpHost(
    WidgetTester tester, {
    SaveTarget? many,
    bool signedIn = true,
    bool restored = true,
    TextScaler textScaler = TextScaler.noScaling,
    Size size = const Size(360, 780),
  }) async {
    final container = await pumpPlaylistsPage(
      tester,
      host(many),
      playlists: server,
      signedIn: signedIn,
      textScaler: textScaler,
      size: size,
    );
    if (restored) {
      await container.read(identityControllerProvider.notifier).restore();
    }
    return container;
  }

  Future<void> tapOpen(WidgetTester tester, {bool many = false}) async {
    await tester.tap(
      many ? find.text('保存选中的歌') : find.bySemanticsLabel('把《晴天》保存到歌单'),
    );
    await settlePage(tester);
  }

  Future<ProviderContainer> openOne(
    WidgetTester tester, {
    bool signedIn = true,
    bool restored = true,
    TextScaler textScaler = TextScaler.noScaling,
    Size size = const Size(360, 780),
  }) async {
    final container = await pumpHost(
      tester,
      signedIn: signedIn,
      restored: restored,
      textScaler: textScaler,
      size: size,
    );
    await tapOpen(tester);
    return container;
  }

  Future<ProviderContainer> openMany(WidgetTester tester) async {
    // 选中的歌来自来源歌单，服务端只复制来源里确实有的歌。
    server.contents['pl-1'] = [song('a'), song('b', source: TrackSource.qq)];
    final container = await pumpHost(tester, many: several);
    await tapOpen(tester, many: true);
    return container;
  }

  Finder row(String name) => find.bySemanticsLabel(RegExp('^$name，'));
  double top(WidgetTester tester, String name) =>
      tester.getTopLeft(find.text(name)).dy;

  Future<void> closeSheet(WidgetTester tester, Finder inside) async {
    Navigator.of(tester.element(inside)).pop();
    await settlePage(tester);
  }

  testWidgets('a guest is asked to sign in, and goes to the account '
      'settings once the sheet is closed', (tester) async {
    final semantics = tester.ensureSemantics();
    await openOne(tester, signedIn: false, restored: false);

    expect(find.text('注册或登录之后就能把歌保存到歌单。'), findsOneWidget);
    expect(find.text('保存到歌单'), findsOneWidget);
    await tester.tap(find.text('去账号设置'));
    await settlePage(tester);

    expect(accountOpened, 1);
    expect(find.text('注册或登录之后就能把歌保存到歌单。'), findsNothing);
    expect(server.calls, isEmpty);
    semantics.dispose();
  });

  testWidgets('it is busy until both the list and the song are read, and '
      'reads each once', (tester) async {
    await pumpHost(tester);
    final listing = server.hold('listMine');
    final reading = server.hold('containing');

    await tapOpen(tester);
    expect(find.byType(PlaylistLoading), findsOneWidget);
    expect(find.text('保存到歌单'), findsOneWidget);
    listing.complete();
    await settlePage(tester);
    expect(find.byType(PlaylistLoading), findsOneWidget);
    expect(find.text('夜跑'), findsNothing);
    reading.complete();
    await settlePage(tester);

    expect(find.byType(PlaylistLoading), findsNothing);
    expect(find.text('夜跑'), findsOneWidget);
    expect(server.count('listMine'), 1);
    expect(server.count('containing'), 1);
  });

  testWidgets('an identity read while the sheet opens still reads each '
      'once', (tester) async {
    final semantics = tester.ensureSemantics();
    await openOne(tester, restored: false);

    expect(
      tester.getSemantics(row('晨跑')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    expect(server.count('listMine'), 1);
    expect(server.count('containing'), 1);
    semantics.dispose();
  });

  testWidgets('the playlists come favourites first and then newest first, '
      'with the song ticked where it is, and keep that order after '
      'saving', (tester) async {
    final semantics = tester.ensureSemantics();
    await openOne(tester);

    expect(find.text('保存到歌单'), findsOneWidget);
    expect(find.text('晴天'), findsOneWidget);
    expect(top(tester, '我喜欢'), lessThan(top(tester, '晨跑')));
    expect(top(tester, '晨跑'), lessThan(top(tester, '夜跑')));
    expect(
      tester.getSemantics(row('晨跑')),
      isSemantics(hasCheckedState: true, isChecked: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(row('夜跑')),
      isSemantics(hasCheckedState: true, isChecked: false),
    );
    expect(find.bySemanticsLabel('夜跑，0 首'), findsOneWidget);

    await tester.tap(row('夜跑'));
    await settlePage(tester);

    expect(server.calls, contains('add pl-1 netease:a'));
    expect(
      tester.getSemantics(row('夜跑')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    expect(
      top(tester, '晨跑'),
      lessThan(top(tester, '夜跑')),
      reason: 'the order is frozen',
    );
    expect(notices, isEmpty);
    semantics.dispose();
  });

  testWidgets('a failed tick is told and rolled back', (tester) async {
    final semantics = tester.ensureSemantics();
    server.failNext('add', apiError('CONFLICT', message: '一个歌单最多 1000 首歌'));
    await openOne(tester);

    await tester.tap(row('夜跑'));
    await settlePage(tester);

    expect(notices, [(ToastKind.failure, '一个歌单最多 1000 首歌')]);
    expect(
      tester.getSemantics(row('夜跑')),
      isSemantics(hasCheckedState: true, isChecked: false),
    );
    semantics.dispose();
  });

  testWidgets('a tick still answers after the sheet is closed', (tester) async {
    final semantics = tester.ensureSemantics();
    await openOne(tester);
    final add = server.hold('add');
    server.failNext('add', apiError('CONFLICT', message: '一个歌单最多 1000 首歌'));

    await tester.tap(row('夜跑'));
    await tester.pump();
    await closeSheet(tester, find.text('保存到歌单'));
    expect(find.text('保存到歌单'), findsNothing);
    add.complete();
    await settlePage(tester);

    expect(notices, [(ToastKind.failure, '一个歌单最多 1000 首歌')]);
    semantics.dispose();
  });

  testWidgets('the sheet keeps working once the page under it is gone', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final showing = ValueNotifier(true);
    addTearDown(showing.dispose);
    final container = await pumpPlaylistsPage(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: showing,
        builder: (_, shown, _) => shown
            ? Consumer(
                builder: (_, ref, _) {
                  ref.watch(myPlaylistsControllerProvider);
                  return host(null);
                },
              )
            : const SizedBox(),
      ),
      playlists: server,
    );
    await container.read(identityControllerProvider.notifier).restore();
    await tapOpen(tester);

    showing.value = false;
    await settlePage(tester);
    expect(find.bySemanticsLabel('把《晴天》保存到歌单'), findsNothing);
    await tester.tap(row('夜跑'));
    await settlePage(tester);

    expect(tester.takeException(), isNull);
    expect(container.exists(myPlaylistsControllerProvider), isTrue);
    expect(server.calls, contains('add pl-1 netease:a'));
    expect(
      tester.getSemantics(row('夜跑')),
      isSemantics(hasCheckedState: true, isChecked: true, isEnabled: true),
    );
    expect(notices, isEmpty);
    semantics.dispose();
  });

  testWidgets('a failed read of the song offers a retry', (tester) async {
    server.failNext('containing', networkError);
    await openOne(tester);

    expect(find.text('读取失败：${networkError.message}'), findsOneWidget);
    expect(find.text('保存到歌单'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await settlePage(tester);

    expect(find.text('夜跑'), findsOneWidget);
  });

  for (final many in [false, true]) {
    testWidgets('a failed read of the list offers a retry '
        '(${many ? 'several songs' : 'one song'})', (tester) async {
      server.failNext('listMine', networkError);
      await pumpHost(tester, many: many ? several : null);
      await tapOpen(tester, many: many);

      expect(find.text('读取失败：${networkError.message}'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await settlePage(tester);

      expect(find.text('晨跑'), findsOneWidget);
      expect(server.count('listMine'), 2);
    });
  }

  testWidgets('a read overtaken by a retry does not start another', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpHost(tester);
    final first = server.hold('containing');
    final second = server.hold('containing');
    server.failNext('listMine', networkError);
    await tapOpen(tester);

    expect(find.text('读取失败：${networkError.message}'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await settlePage(tester);
    first.complete();
    await settlePage(tester);
    second.complete();
    await settlePage(tester);

    expect(server.count('containing'), 2);
    expect(
      tester.getSemantics(row('晨跑')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    semantics.dispose();
  });

  testWidgets('a retry on its way out cannot be tapped again', (tester) async {
    server.failNext('containing', networkError);
    await openOne(tester);
    final reading = server.hold('containing');

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('重试'), warnIfMissed: false);
    reading.complete();
    await settlePage(tester);

    expect(server.count('containing'), 2);
  });

  testWidgets('switching to the form keeps the old and the new content '
      'top-aligned', (tester) async {
    await openOne(tester);

    await tester.tap(find.text('新建歌单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final leaving = find.byKey(const ValueKey('titled'));
    final arriving = find.byKey(const ValueKey('create'));
    expect(leaving, findsOneWidget);
    expect(arriving, findsOneWidget);
    expect(tester.getTopLeft(arriving).dy, tester.getTopLeft(leaving).dy);
  });

  testWidgets('switching from a failure to loading keeps both top-aligned', (
    tester,
  ) async {
    server.failNext('containing', networkError);
    await openOne(tester);
    final reading = server.hold('containing');

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final leaving = find.byKey(const ValueKey('failure'));
    final arriving = find.byKey(const ValueKey('loading'));
    expect(leaving, findsOneWidget);
    expect(arriving, findsOneWidget);
    expect(tester.getTopLeft(arriving).dy, tester.getTopLeft(leaving).dy);
    reading.complete();
    await settlePage(tester);
  });

  testWidgets('opened over a list read before, it reads the list and the '
      'song again and freezes the order it reads', (tester) async {
    final semantics = tester.ensureSemantics();
    final container = await openOne(tester);
    final alive = container.listen(myPlaylistsControllerProvider, (_, _) {});
    addTearDown(alive.close);
    await closeSheet(tester, find.text('保存到歌单'));
    server
      ..playlists.add(playlist('pl-3', name: '散步', updatedAtMs: 7))
      ..contents['pl-3'] = []
      ..contents['pl-1'] = [song('a')];
    final lists = server.count('listMine');
    final reads = server.count('containing');
    final reading = server.hold('containing');

    await tapOpen(tester);

    expect(find.byType(PlaylistLoading), findsOneWidget);
    expect(find.text('夜跑'), findsNothing);
    reading.complete();
    await settlePage(tester);

    expect(top(tester, '晨跑'), lessThan(top(tester, '散步')));
    expect(top(tester, '散步'), lessThan(top(tester, '夜跑')));
    expect(
      tester.getSemantics(row('夜跑')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    expect(server.count('listMine'), lists + 1);
    expect(server.count('containing'), reads + 1);
    semantics.dispose();
  });

  testWidgets('a new playlist made here gets the song and the focus; a '
      'cancel gives the focus back to the new playlist row', (tester) async {
    await openOne(tester);

    await tester.tap(find.text('新建歌单'));
    await settlePage(tester);
    expect(
      tester.testTextInput.isVisible,
      isFalse,
      reason: 'the name field does not raise the keyboard by itself',
    );
    await tester.tap(find.text('取消'));
    await settlePage(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'new playlist');

    await tester.tap(find.text('新建歌单'));
    await settlePage(tester);
    await tester.enterText(find.byType(EditableText), '散步');
    await tester.pump();
    await tester.tap(find.text('创建'));
    await settlePage(tester);

    expect(find.text('散步'), findsOneWidget);
    expect(server.calls, contains('add new-1 netease:a'));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'playlist new-1');
    expect(
      top(tester, '夜跑'),
      lessThan(top(tester, '散步')),
      reason: 'a playlist that shows up later goes last',
    );
  });

  testWidgets('going back to the list before the switch has finished keeps '
      'the focus', (tester) async {
    await openOne(tester);

    await tester.tap(find.text('新建歌单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('取消'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await settlePage(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('新建歌单'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'new playlist');
  });

  testWidgets('a create on its way out cannot be sent again', (tester) async {
    final semantics = tester.ensureSemantics();
    await openOne(tester);
    await tester.tap(find.text('新建歌单'));
    await settlePage(tester);
    await tester.enterText(find.byType(EditableText), '散步');
    await tester.pump();

    await tester.tap(find.text('创建'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('创建'), findsOneWidget, reason: 'still fading out');
    expect(find.semantics.byLabel('创建'), findsNothing);
    await tester.tap(find.text('创建'), warnIfMissed: false);
    await settlePage(tester);

    expect(server.count('create'), 1);
    semantics.dispose();
  });

  testWidgets('a new playlist at the end of a long list is scrolled into '
      'view', (tester) async {
    for (var index = 3; index <= 14; index++) {
      server
        ..playlists.add(
          playlist('pl-$index', name: '歌单$index', updatedAtMs: 20 + index),
        )
        ..contents['pl-$index'] = [];
    }
    await openOne(tester, size: const Size(360, 640));
    await tester.ensureVisible(find.text('新建歌单'));
    await settlePage(tester);
    await tester.tap(find.text('新建歌单'));
    await settlePage(tester);
    await tester.enterText(find.byType(EditableText), '散步');
    await tester.pump();
    await tester.tap(find.text('创建'));
    await settlePage(tester);

    final shown = tester.getRect(find.text('散步'));
    expect(shown.top, greaterThanOrEqualTo(0));
    expect(shown.bottom, lessThanOrEqualTo(640));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'playlist new-1');
  });

  testWidgets('with reduced motion the content switches at once', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await openOne(tester);

    await tester.tap(find.text('新建歌单'));
    await tester.pump();
    await tester.pump();

    expect(find.text('保存到歌单'), findsNothing);
    expect(find.text('歌单名'), findsOneWidget);
  });

  for (final (width, scale) in [(360.0, 2.0), (320.0, 3.0)]) {
    testWidgets('at $width dp and ${scale}x text it fits', (tester) async {
      await openOne(
        tester,
        textScaler: TextScaler.linear(scale),
        size: Size(width, 780),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(row('夜跑')).height,
        greaterThanOrEqualTo(AlistenSizes.minTouchTarget),
      );
    });
  }

  testWidgets('a guest who becomes an account keeps the sheet open', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final container = await openOne(tester, signedIn: false);
    expect(find.text('注册或登录之后就能把歌保存到歌单。'), findsOneWidget);

    final identity = container.read(identityControllerProvider);
    container
        .read(identityControllerProvider.notifier)
        .updateAccount(identity.member!.id, testAccount);
    await settlePage(tester);

    expect(find.text('注册或登录之后就能把歌保存到歌单。'), findsNothing);
    expect(
      tester.getSemantics(row('晨跑')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    semantics.dispose();
  });

  testWidgets('a refused tick closes the sheet and is told once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    server.failNext('add', apiError('UNAUTHORIZED', status: 401));
    await openOne(tester);

    await tester.tap(row('夜跑'));
    await settlePage(tester);

    expect(find.text('保存到歌单'), findsNothing);
    expect(find.text('注册或登录之后就能把歌保存到歌单。'), findsNothing);
    expect(notices, [(ToastKind.failure, signedOutNotice)]);
    semantics.dispose();
  });

  testWidgets('saving several songs leaves out where they come from, needs '
      'a target, and tells one notice for all', (tester) async {
    final semantics = tester.ensureSemantics();
    await openMany(tester);

    expect(find.text('已选 2 首'), findsOneWidget);
    expect(find.text('夜跑'), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('保存')),
      isSemantics(isEnabled: false, hasEnabledState: true, isButton: true),
    );

    await tester.tap(row('晨跑'));
    await tester.pump();
    await tester.tap(row('我喜欢'));
    await tester.pump();
    expect(
      tester.getSemantics(row('晨跑')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    await tester.tap(find.text('保存'));
    await settlePage(tester);

    expect(notices, [(ToastKind.success, '已保存到 2 个歌单，其中 1 首已经在里面')]);
    expect(find.text('已选 2 首'), findsNothing);
    semantics.dispose();
  });

  testWidgets('while saving several songs nothing else can be chosen and '
      'the sheet stays open', (tester) async {
    final semantics = tester.ensureSemantics();
    await openMany(tester);
    final copy = server.hold('copy');

    await tester.tap(row('晨跑'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(
      tester.getSemantics(row('我喜欢')),
      isSemantics(hasEnabledState: true, isEnabled: false),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('新建歌单')),
      isSemantics(hasEnabledState: true, isEnabled: false),
    );
    await Navigator.of(tester.element(find.text('已选 2 首'))).maybePop();
    await tester.pump();
    expect(find.text('已选 2 首'), findsOneWidget);

    copy.complete();
    await settlePage(tester);
    expect(find.text('已选 2 首'), findsNothing);
    expect(notices, [(ToastKind.success, '已保存到“晨跑”，其中 1 首已经在里面')]);
    semantics.dispose();
  });

  testWidgets('saving several songs where only some go in tells one notice '
      'as bad as the worst', (tester) async {
    final semantics = tester.ensureSemantics();
    server.failNext(
      'copy',
      apiError('NOT_FOUND', message: '歌单不存在', status: 404),
    );
    await openMany(tester);

    await tester.tap(row('我喜欢'));
    await tester.pump();
    await tester.tap(row('晨跑'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await settlePage(tester);

    expect(notices, [
      (ToastKind.failure, '已保存到“晨跑”，其中 1 首已经在里面\n没能保存到“我喜欢”：歌单不存在'),
    ]);
    semantics.dispose();
  });

  testWidgets('saving several songs where one target was not sent tells '
      'one warning', (tester) async {
    final semantics = tester.ensureSemantics();
    server.failNext(
      'copy',
      apiError('RATE_LIMITED', message: '请求太频繁，请稍后再试。', status: 429),
    );
    await openMany(tester);

    await tester.tap(row('我喜欢'));
    await tester.pump();
    await tester.tap(row('晨跑'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await settlePage(tester);

    expect(notices, [
      (ToastKind.warning, '已保存到“晨跑”，其中 1 首已经在里面\n没能保存到“我喜欢”：请求太频繁，请稍后再试。'),
    ]);
    semantics.dispose();
  });

  testWidgets('a new playlist made while saving several songs is chosen', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await openMany(tester);

    await tester.tap(find.text('新建歌单'));
    await settlePage(tester);
    await tester.enterText(find.byType(EditableText), '散步');
    await tester.pump();
    await tester.tap(find.text('创建'));
    await settlePage(tester);

    expect(
      tester.getSemantics(row('散步')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'playlist new-1');
    expect(server.calls, isNot(contains(startsWith('add '))));
    await tester.tap(find.text('保存'));
    await settlePage(tester);

    expect(server.calls, contains('copy pl-1>new-1 netease:a,qq:b'));
    expect(notices, [(ToastKind.success, '已保存到“散步”')]);
    semantics.dispose();
  });

  testWidgets('saving several songs over a list read before reads it again '
      'first', (tester) async {
    final container = await openMany(tester);
    final alive = container.listen(myPlaylistsControllerProvider, (_, _) {});
    addTearDown(alive.close);
    await closeSheet(tester, find.text('已选 2 首'));
    server
      ..playlists.add(playlist('pl-3', name: '散步', updatedAtMs: 7))
      ..contents['pl-3'] = [];
    final lists = server.count('listMine');
    final reading = server.hold('listMine');

    await tapOpen(tester, many: true);

    expect(find.byType(PlaylistLoading), findsOneWidget);
    reading.complete();
    await settlePage(tester);

    expect(top(tester, '晨跑'), lessThan(top(tester, '散步')));
    expect(top(tester, '散步'), lessThan(top(tester, '新建歌单')));
    expect(server.count('listMine'), lists + 1);
    expect(server.count('containing'), 0);
  });

  testWidgets('a server switch closes the sheet, even under another one', (
    tester,
  ) async {
    final container = await openMany(tester);
    unawaited(
      showSheetPanel<void>(
        tester.element(find.text('已选 2 首')),
        builder: (_) => const Text('盖在上面'),
      ),
    );
    await settlePage(tester);

    unawaited(
      container
          .read(identityControllerProvider.notifier)
          .resetForServerChange(),
    );
    await settlePage(tester);

    expect(find.text('已选 2 首'), findsNothing);
    expect(find.text('盖在上面'), findsOneWidget);
    expect(server.calls, isNot(contains(startsWith('copy '))));
  });

  group('copySummary', () {
    final night = playlist('pl-1', name: '夜跑');
    final morning = playlist('pl-2', name: '晨跑');

    test('one target is named', () {
      expect(copySummary([(night, const MutationSucceeded(2))], 2), [
        (ToastKind.success, '已保存到“夜跑”'),
      ]);
    });

    test('songs already there are counted over every target', () {
      expect(
        copySummary([
          (night, const MutationSucceeded(1)),
          (morning, const MutationSucceeded(0)),
        ], 2),
        [(ToastKind.success, '已保存到 2 个歌单，其中 3 首已经在里面')],
      );
    });

    test('each failed target has its own notice; a refusal is told '
        'once', () {
      expect(
        copySummary([
          (night, const MutationFailed('NOT_FOUND', '歌单不存在')),
          (morning, const MutationFailed('UNAUTHORIZED', '已退出登录')),
          (
            playlist('fav', name: '我喜欢'),
            const MutationFailed('UNAUTHORIZED', '已退出登录'),
          ),
          (playlist('pl-3', name: '散步'), const MutationUnknown()),
          (playlist('pl-4', name: '通勤'), const MutationNotSent('请求太频繁，请稍后再试。')),
        ], 2),
        [
          (ToastKind.failure, '没能保存到“夜跑”：歌单不存在'),
          (ToastKind.warning, '保存到“散步”的结果未知，已重新读取'),
          (ToastKind.warning, '没能保存到“通勤”：请求太频繁，请稍后再试。'),
          (ToastKind.failure, '已退出登录'),
        ],
      );
    });

    test('a server switch is told once, however many targets it '
        'stopped', () {
      expect(
        copySummary([
          (night, const MutationNotSent(serverChangedNotice)),
          (morning, const MutationNotSent(serverChangedNotice)),
        ], 2),
        [(ToastKind.warning, serverChangedNotice)],
      );
    });
  });
}
