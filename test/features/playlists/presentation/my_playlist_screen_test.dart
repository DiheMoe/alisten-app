import 'dart:async';

import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/application/my_playlist_controller.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/presentation/my_playlist_screen.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/pick_controller.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../playlists_page_harness.dart';
import '../playlists_test_doubles.dart';

const _bilibili = 'https://www.bilibili.com/video/BV1xx411c7mD';
const _web = 'https://example.com/a.mp3';

void main() {
  late FakePlaylistApi server;
  late FakePlaylistExporter exporter;
  late List<(ToastKind, String)> notices;
  late List<String> titles;
  late int deleted;
  late int accountOpened;
  late ProviderContainer container;
  String? copied;

  setUp(() {
    notices = [];
    titles = [];
    deleted = 0;
    accountOpened = 0;
    copied = null;
    exporter = FakePlaylistExporter();
    server = FakePlaylistApi()
      ..playlists.addAll([
        favoritesPlaylist,
        playlist('pl-1', name: '夜跑', trackCount: 4),
      ])
      ..contents['fav'] = []
      ..contents['pl-1'] = [song('a'), song('b'), song('c'), song('d')];
  });

  Widget screen([String id = 'pl-1']) => MyPlaylistScreen(
    id: id,
    onResult: (_, _) {},
    onNotice: (kind, text) => notices.add((kind, text)),
    onCopyTitle: titles.add,
    onOpenAccount: () => accountOpened++,
    onDeleted: () => deleted++,
  );

  // [showing] 为 false 时页面离开组件树，就像链接或通知换掉了外壳里的页面，
  // 而根导航器上的面板还开着。
  Widget page(String id, ValueNotifier<bool>? showing, bool reduceMotion) {
    Widget child = showing == null
        ? screen(id)
        : ValueListenableBuilder<bool>(
            valueListenable: showing,
            builder: (_, shown, _) => shown ? screen(id) : const SizedBox(),
          );
    if (reduceMotion) {
      final inner = child;
      child = Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: inner,
        ),
      );
    }
    return child;
  }

  // 叠在另一个页面之上，返回手势才会经过页面自己的 PopScope。
  Future<void> open(
    WidgetTester tester, {
    String id = 'pl-1',
    RoomKind? room,
    TextScaler textScaler = TextScaler.noScaling,
    bool signedIn = true,
    ValueNotifier<bool>? showing,
    bool reduceMotion = false,
    Size size = const Size(360, 780),
    List<Override> overrides = const [],
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    container = await pumpPlaylistsPage(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => page(id, showing, reduceMotion),
              ),
            ),
          ),
          child: const Text('打开歌单'),
        ),
      ),
      playlists: server,
      exporter: exporter,
      signedIn: signedIn,
      textScaler: textScaler,
      size: size,
      overrides: [
        ...overrides,
        if (room != null)
          roomControllerProvider.overrideWithBuild(
            (ref, _) => RoomState(
              status: RoomConnectionStatus.open,
              activeRoomId: 'room-id',
              snapshot: testRoomSnapshot().copyWith(
                term: 1,
                seq: 1,
                room: RoomInfo(
                  id: 'room-id',
                  name: '一起听',
                  description: '',
                  kind: room,
                ),
              ),
            ),
          ),
      ],
    );
    await tester.tap(find.text('打开歌单'));
    await settlePage(tester);
    await settlePage(tester);
  }

  int reorderAction(String label) =>
      CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: label));

  bool hasAction(SemanticsNode node, int action) =>
      node.getSemanticsData().customSemanticsActionIds?.contains(action) ??
      false;

  void reorder(WidgetTester tester, String title, String label) {
    final action = reorderAction(label);
    tester.semantics.performAction(
      find.semantics.byPredicate(
        (node) => hasAction(node, action) && node.label.contains(title),
      ),
      SemanticsAction.customAction,
      args: action,
    );
  }

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  Future<void> openMenu(WidgetTester tester, [String name = '夜跑']) async {
    await tester.tap(find.bySemanticsLabel('“$name”的更多操作'));
    await settlePage(tester);
  }

  void expectNoFocusedField(WidgetTester tester) {
    for (final field in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(field.focusNode.hasFocus, isFalse);
    }
    expect(tester.testTextInput.isVisible, isFalse);
  }

  testWidgets('the header tells the songs and the dates, and the songs '
      'cannot be picked outside a room', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    expect(find.text('夜跑'), findsOneWidget);
    expect(find.textContaining('4 首，更新于'), findsOneWidget);
    expect(find.text('进入房间后可点歌'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('点歌《歌a》')),
      isSemantics(isEnabled: false, hasEnabledState: true),
    );
    semantics.dispose();
  });

  testWidgets('in an ephemeral room a web link cannot be picked, a Bilibili '
      'link can', (tester) async {
    final semantics = tester.ensureSemantics();
    server.contents['pl-1'] = [
      song(_web, title: '网页', source: TrackSource.link),
      song(_bilibili, title: '视频', source: TrackSource.link),
    ];
    await open(tester, room: RoomKind.ephemeral);

    expect(
      tester.getSemantics(find.bySemanticsLabel('临时房间不能点链接里的歌')),
      isSemantics(isEnabled: false, hasEnabledState: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('点歌《视频》')),
      isSemantics(isEnabled: true, hasEnabledState: true),
    );
    semantics.dispose();
  });

  testWidgets('the menu offers sharing before a share, and the link '
      'actions after', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    await openMenu(tester);
    for (final label in ['重命名', '分享', '导出', '删除']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('复制分享链接'), findsNothing);

    await tester.tap(find.text('分享'));
    await settlePage(tester);
    expect(notices.last, (ToastKind.success, '已开启分享，链接已复制'));
    final host = container.read(appConfigProvider).linkHost;
    expect(copied, 'https://$host/s/$shareIdA');

    await openMenu(tester);
    for (final label in ['复制分享链接', '重新生成分享链接', '停止分享']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('分享'), findsNothing);

    await tester.tap(find.text('重新生成分享链接'));
    await settlePage(tester);
    expect(find.text('生成新链接之后，之前分享出去的链接就打不开了。'), findsOneWidget);
    await tester.tap(find.widgetWithText(PillButton, '重新生成'));
    await settlePage(tester);
    expect(notices.last, (ToastKind.success, '已生成新链接并复制'));
    expect(copied, 'https://$host/s/$shareIdB');

    copied = null;
    await openMenu(tester);
    await tester.tap(find.text('复制分享链接'));
    await settlePage(tester);
    expect(notices.last, (ToastKind.success, '已复制分享链接'));
    expect(copied, 'https://$host/s/$shareIdB');

    await openMenu(tester);
    await tester.tap(find.text('停止分享'));
    await settlePage(tester);
    expect(find.text('停止之后，分享出去的链接就打不开了。'), findsOneWidget);
    await tester.tap(find.widgetWithText(PillButton, '停止分享'));
    await settlePage(tester);
    expect(notices.last, (ToastKind.success, '已停止分享'));
    expect(server.calls, contains('unshare pl-1'));
    semantics.dispose();
  });

  testWidgets('while a share is sent a second tap sends nothing', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    final sharing = server.hold('share');

    await openMenu(tester);
    await tester.tap(find.text('分享'));
    await settlePage(tester);
    await openMenu(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('分享')),
      isSemantics(isEnabled: false, hasEnabledState: true),
    );
    await tester.tap(find.text('分享'));
    await settlePage(tester);

    sharing.complete();
    await settlePage(tester);
    expect(server.count('share'), 1);
    expect(notices, [(ToastKind.success, '已开启分享，链接已复制')]);
    semantics.dispose();
  });

  testWidgets('while sharing is being stopped the link actions are off', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    server.playlists[1] = server.playlists[1].copyWith(shareId: shareIdA);
    await open(tester);
    final stopping = server.hold('unshare');

    await openMenu(tester);
    await tester.tap(find.text('停止分享'));
    await settlePage(tester);
    await tester.tap(find.widgetWithText(PillButton, '停止分享'));
    await settlePage(tester);
    await openMenu(tester);
    for (final label in ['重新生成分享链接', '停止分享']) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(isEnabled: false, hasEnabledState: true),
        reason: label,
      );
    }

    stopping.complete();
    await settlePage(tester);
    expect(server.count('unshare'), 1);
    semantics.dispose();
  });

  testWidgets('favorites can be shared and exported, nothing more', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    server.contents['fav'] = [song('a')];
    await open(tester, id: 'fav');

    await openMenu(tester, '我喜欢');

    expect(find.text('分享'), findsOneWidget);
    expect(find.text('导出'), findsOneWidget);
    expect(find.text('重命名'), findsNothing);
    expect(find.text('删除'), findsNothing);
    semantics.dispose();
  });

  testWidgets('renaming keeps the field unfocused and saves the new name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    await openMenu(tester);
    await tester.tap(find.text('重命名'));
    await settlePage(tester);

    expect(find.widgetWithText(PillButton, '保存'), findsOneWidget);
    expect(find.widgetWithText(PillButton, '取消'), findsNothing);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '夜跑',
    );
    expectNoFocusedField(tester);

    await tester.enterText(find.byType(EditableText), '散步');
    await tester.tap(find.widgetWithText(PillButton, '保存'));
    await settlePage(tester);

    expect(server.calls, contains('rename pl-1 散步'));
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('散步'), findsOneWidget);
    expect(notices, isEmpty);
    semantics.dispose();
  });

  testWidgets('a rename that answers under another sheet closes only the '
      'rename sheet', (tester) async {
    await open(tester);
    await openMenu(tester);
    await tester.tap(find.text('重命名'));
    await settlePage(tester);
    final answer = server.hold('rename');
    await tester.enterText(find.byType(EditableText), '散步');
    await tester.tap(find.widgetWithText(PillButton, '保存'));
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting: the bar, all and none, and one song removed '
      'without asking', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    await tester.tap(find.text('选择'));
    await settlePage(tester);
    expect(find.text('已选 0 首'), findsOneWidget);
    for (final label in [
      '把选中的歌保存到歌单',
      '把选中的歌移到最前',
      '把选中的歌移到最后',
      '把选中的歌移出这个歌单',
    ]) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(isEnabled: false, hasEnabledState: true),
        reason: label,
      );
    }

    await tester.tap(find.bySemanticsLabel('歌a'));
    await tester.pump();
    expect(find.text('已选 1 首'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('已选 1 首')),
      isSemantics(isLiveRegion: true, isHeader: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('歌a')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('歌b')),
      isSemantics(hasCheckedState: true, isChecked: false),
    );

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.text('已选 4 首'), findsOneWidget);
    await tester.tap(find.text('取消全选'));
    await tester.pump();
    expect(find.text('已选 0 首'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('歌a'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('把选中的歌移出这个歌单'));
    await settlePage(tester);
    expect(find.text('移出歌曲'), findsNothing);
    expect(server.calls, contains('remove pl-1 netease:a'));
    semantics.dispose();
  });

  testWidgets('removing several songs asks first; moving to the top sends '
      'one move', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    await tester.tap(find.text('选择'));
    await settlePage(tester);
    await tester.tap(find.bySemanticsLabel('歌c'));
    await tester.tap(find.bySemanticsLabel('歌d'));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('把选中的歌移到最前'));
    await settlePage(tester);
    expect(
      server.calls,
      contains('move pl-1 netease:c,netease:d before netease:a'),
    );
    expect(top(tester, '歌d'), lessThan(top(tester, '歌a')));

    await tester.tap(find.bySemanticsLabel('把选中的歌移出这个歌单'));
    await settlePage(tester);
    expect(find.text('把 2 首歌移出这个歌单？'), findsOneWidget);
    await tester.tap(find.widgetWithText(PillButton, '移出'));
    await settlePage(tester);
    expect(server.calls, contains('remove pl-1 netease:c,netease:d'));
    expect(find.text('歌c'), findsNothing);
    semantics.dispose();
  });

  testWidgets('moving the selection to the bottom sends no before', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    await tester.tap(find.text('选择'));
    await settlePage(tester);
    await tester.tap(find.bySemanticsLabel('歌a'));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('把选中的歌移到最后'));
    await settlePage(tester);

    expect(server.calls, contains('move pl-1 netease:a'));
    semantics.dispose();
  });

  testWidgets('selected songs are saved to another playlist, never to this '
      'one', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    await tester.tap(find.text('选择'));
    await settlePage(tester);
    await tester.tap(find.bySemanticsLabel('歌a'));
    await tester.tap(find.bySemanticsLabel('歌b'));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('把选中的歌保存到歌单'));
    await settlePage(tester);
    expect(find.bySemanticsLabel(RegExp('^夜跑，')), findsNothing);
    await tester.tap(find.bySemanticsLabel(RegExp('^我喜欢，')));
    await tester.pump();
    await tester.tap(find.widgetWithText(PillButton, '保存'));
    await settlePage(tester);

    expect(server.calls, contains('copy pl-1>fav netease:a,netease:b'));
    expect(notices.last, (ToastKind.success, '已保存到“我喜欢”'));
    semantics.dispose();
  });

  testWidgets("a song's own menu saves it elsewhere and removes it without "
      'asking', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    await tester.tap(find.bySemanticsLabel('《歌b》的更多操作'));
    await settlePage(tester);
    await tester.tap(find.text('保存到歌单').hitTestable());
    await settlePage(tester);
    expect(server.calls, contains('containing netease:b'));
    Navigator.of(tester.element(find.text('新建歌单'))).pop();
    await settlePage(tester);

    await tester.tap(find.bySemanticsLabel('《歌b》的更多操作'));
    await settlePage(tester);
    await tester.tap(find.text('移出这个歌单'));
    await settlePage(tester);

    expect(find.text('移出歌曲'), findsNothing);
    expect(server.calls, contains('remove pl-1 netease:b'));
    semantics.dispose();
  });

  testWidgets('a screen reader moves a song down on the row that names it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    expect(
      find.semantics.byPredicate(
        (node) => hasAction(node, reorderAction('下移')) && node.label.isEmpty,
      ),
      findsNothing,
    );
    reorder(tester, '歌a', '下移');
    await settlePage(tester);

    expect(server.calls, contains('move pl-1 netease:a before netease:c'));
    expect(top(tester, '歌b'), lessThan(top(tester, '歌a')));
    semantics.dispose();
  });

  testWidgets('a refused move is told and the order comes back', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    server.failNext('move', apiError('CONFLICT', message: '歌单已经变了，刷新之后再试'));
    await open(tester);

    reorder(tester, '歌a', '移到末尾');
    await settlePage(tester);

    expect(notices.last, (ToastKind.failure, '歌单已经变了，刷新之后再试'));
    expect(top(tester, '歌a'), lessThan(top(tester, '歌b')));
    semantics.dispose();
  });

  testWidgets('a long press copies a title; while selecting a song is dragged '
      'by its handle', (tester) async {
    await open(tester);
    final rowHeight = top(tester, '歌b') - top(tester, '歌a');

    await tester.longPress(find.text('歌b'));
    await settlePage(tester);
    expect(titles, ['歌b']);
    expect(server.count('move'), 0);

    await tester.tap(find.text('选择'));
    await settlePage(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.drag_handle_rounded).first),
    );
    await tester.pump();
    for (var step = 0; step < 10; step++) {
      await gesture.moveBy(Offset(0, rowHeight * 2.1 / 10));
      await tester.pump();
    }
    await gesture.up();
    await settlePage(tester);

    expect(server.calls, contains('move pl-1 netease:a before netease:d'));
    expect(top(tester, '歌c'), lessThan(top(tester, '歌a')));
    expect(top(tester, '歌a'), lessThan(top(tester, '歌d')));
  });

  testWidgets('selecting swaps the pick buttons and the song menus for the '
      'drag handles', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);
    expect(find.bySemanticsLabel('点歌《歌a》'), findsOneWidget);
    expect(find.bySemanticsLabel('《歌a》的更多操作'), findsOneWidget);

    await tester.tap(find.text('选择'));
    await settlePage(tester);

    expect(find.byIcon(Icons.drag_handle_rounded), findsWidgets);
    expect(find.bySemanticsLabel('点歌《歌a》'), findsNothing);
    expect(find.bySemanticsLabel('《歌a》的更多操作'), findsNothing);
    semantics.dispose();
  });

  testWidgets('while selecting a screen reader still moves a song on the row '
      'that names it and tells whether it is chosen', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    await tester.tap(find.text('选择'));
    await settlePage(tester);

    expect(
      find.semantics.byPredicate(
        (node) => hasAction(node, reorderAction('下移')) && node.label.isEmpty,
      ),
      findsNothing,
    );
    final row = tester.getSemantics(find.bySemanticsLabel('歌a'));
    expect(
      row,
      isSemantics(hasCheckedState: true, isChecked: false, hasTapAction: true),
    );
    expect(hasAction(row, reorderAction('下移')), isTrue);
    reorder(tester, '歌a', '下移');
    await settlePage(tester);

    expect(server.calls, contains('move pl-1 netease:a before netease:c'));
    expect(top(tester, '歌b'), lessThan(top(tester, '歌a')));
    expect(find.text('已选 0 首'), findsOneWidget, reason: 'still selecting');
    semantics.dispose();
  });

  testWidgets('once selecting stops the selection bar is not read, also '
      'while it slides away', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    await tester.tap(find.text('选择'));
    await settlePage(tester);
    expect(find.semantics.byLabel('把选中的歌移到最前'), findsOne);

    await tester.tap(find.bySemanticsLabel('退出选择'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('移到最前'), findsOneWidget, reason: 'still sliding away');
    expect(find.semantics.byLabel('把选中的歌移到最前'), findsNothing);
    await settlePage(tester);

    expect(find.semantics.byLabel('把选中的歌移到最前'), findsNothing);
    semantics.dispose();
  });

  testWidgets('going back while selecting only stops selecting', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('选择'));
    await settlePage(tester);

    await tester.binding.handlePopRoute();
    await settlePage(tester);

    expect(find.text('已选 0 首'), findsNothing);
    expect(find.text('夜跑'), findsOneWidget);
  });

  testWidgets('a playlist that is gone says so and leads back', (tester) async {
    await open(tester, id: 'missing');

    expect(find.text('这个歌单不存在了'), findsOneWidget);
    await tester.tap(find.text('返回我的歌单'));
    expect(deleted, 1);
  });

  testWidgets('a playlist removed elsewhere while selecting stops the '
      'selection and says it is gone', (tester) async {
    await open(tester);
    await tester.tap(find.text('选择'));
    await settlePage(tester);

    // 读取曲目先说不在了，列表还没重新读到：页面上的歌单还在。
    server.playlists.removeWhere((playlist) => playlist.id == 'pl-1');
    final listing = server.hold('listMine');
    unawaited(
      container.read(myPlaylistControllerProvider('pl-1').notifier).load(),
    );
    await settlePage(tester);

    expect(find.text('这个歌单不存在了'), findsOneWidget);
    expect(find.text('已选 0 首'), findsNothing);
    expect(find.text('移到最前').hitTestable(), findsNothing);

    listing.complete();
    await settlePage(tester);
    expect(find.text('这个歌单不存在了'), findsOneWidget);
    expect(find.text('已选 0 首'), findsNothing);
  });

  testWidgets('a guest is sent to the account settings', (tester) async {
    await open(tester, signedIn: false);

    expect(find.text('收藏你喜欢的歌'), findsOneWidget);
    await tester.tap(find.text('去账号设置'));
    expect(accountOpened, 1);
    expect(server.calls, isEmpty);
  });

  testWidgets('a failed read of the songs keeps the header and offers a '
      'retry', (tester) async {
    server.failNext('items', networkError);
    await open(tester);

    expect(find.text('夜跑'), findsOneWidget);
    expect(find.text('读取失败：${networkError.message}'), findsOneWidget);
    expect(find.text('选择'), findsNothing);

    await tester.tap(find.text('重试'));
    await settlePage(tester);
    expect(find.text('歌a'), findsOneWidget);
  });

  testWidgets('an empty playlist says where songs come from', (tester) async {
    server.contents['pl-1'] = [];
    await open(tester);

    expect(find.text('这个歌单还是空的'), findsOneWidget);
    expect(find.text('在播放器、队列和播放历史里，可以把歌保存到歌单。'), findsOneWidget);
    expect(find.text('选择'), findsNothing);
  });

  testWidgets('exporting shows that it is busy and points at the menu', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    final reading = server.hold('items');

    await openMenu(tester);
    await tester.tap(find.text('导出'));
    await settlePage(tester);
    expect(find.bySemanticsLabel('正在导出'), findsOneWidget);
    await openMenu(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('导出')),
      isSemantics(isEnabled: false, hasEnabledState: true),
    );
    await tester.tapAt(const Offset(10, 400));
    await settlePage(tester);

    reading.complete();
    await settlePage(tester);
    expect(find.bySemanticsLabel('正在导出'), findsNothing);
    final export = exporter.exports.single;
    expect(export.name, '夜跑');
    expect(export.items, hasLength(4));
    final menu = tester.getRect(find.bySemanticsLabel('“夜跑”的更多操作'));
    expect(export.origin?.overlaps(menu), isTrue);
    expect(notices, isEmpty);
    semantics.dispose();
  });

  testWidgets('deleting returns to the list without saying the playlist is '
      'gone', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    await openMenu(tester);
    await tester.tap(find.text('删除'));
    await settlePage(tester);
    expect(find.text('删除“夜跑”之后，里面的歌也一起删除。'), findsOneWidget);
    await tester.tap(find.widgetWithText(PillButton, '删除'));
    await settlePage(tester);

    expect(server.calls, contains('delete pl-1'));
    expect(deleted, 1);
    expect(find.text('这个歌单不存在了'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a failed delete is told and stays on the page', (tester) async {
    final semantics = tester.ensureSemantics();
    server.failNext('delete', apiError('CONFLICT', message: '服务端消息'));
    await open(tester);

    await openMenu(tester);
    await tester.tap(find.text('删除'));
    await settlePage(tester);
    await tester.tap(find.widgetWithText(PillButton, '删除'));
    await settlePage(tester);

    expect(notices, [(ToastKind.failure, '服务端消息')]);
    expect(deleted, 0);
    expect(find.text('夜跑'), findsOneWidget);
    semantics.dispose();
  });

  group('a sheet left open after the page goes away', () {
    late ValueNotifier<bool> showing;

    setUp(() => showing = ValueNotifier(true));
    tearDown(() => showing.dispose());

    // 页面原本是控制器唯一的监听者：离开之后还活着，靠的是开着的面板。
    Future<void> leave(WidgetTester tester) async {
      showing.value = false;
      await settlePage(tester);
      expect(find.byType(MyPlaylistScreen), findsNothing);
      expect(container.exists(myPlaylistsControllerProvider), isTrue);
    }

    testWidgets('still renames', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, showing: showing);
      await openMenu(tester);
      await tester.tap(find.text('重命名'));
      await settlePage(tester);

      await leave(tester);
      await tester.enterText(find.byType(EditableText), '散步');
      await tester.tap(find.widgetWithText(PillButton, '保存'));
      await settlePage(tester);

      expect(tester.takeException(), isNull);
      expect(server.calls, contains('rename pl-1 散步'));
      expect(find.byType(EditableText), findsNothing);
      expect(deleted, 0);
      semantics.dispose();
    });

    testWidgets('a first share answered after leaving still copies the link '
        'and tells it', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, showing: showing);
      final sharing = server.hold('share');
      await openMenu(tester);
      await tester.tap(find.text('分享'));
      await settlePage(tester);

      await leave(tester);
      sharing.complete();
      await settlePage(tester);

      expect(tester.takeException(), isNull);
      final host = container.read(appConfigProvider).linkHost;
      expect(copied, 'https://$host/s/$shareIdA');
      expect(notices, [(ToastKind.success, '已开启分享，链接已复制')]);
      semantics.dispose();
    });

    testWidgets('still stops sharing and tells it', (tester) async {
      final semantics = tester.ensureSemantics();
      server.playlists[1] = server.playlists[1].copyWith(shareId: shareIdA);
      await open(tester, showing: showing);
      await openMenu(tester);
      await tester.tap(find.text('停止分享'));
      await settlePage(tester);

      await leave(tester);
      await tester.tap(find.widgetWithText(PillButton, '停止分享'));
      await settlePage(tester);

      expect(tester.takeException(), isNull);
      expect(server.calls, contains('unshare pl-1'));
      expect(notices, [(ToastKind.success, '已停止分享')]);
      expect(find.text('停止之后，分享出去的链接就打不开了。'), findsNothing);
      semantics.dispose();
    });

    testWidgets('a page shown again before the answer keeps its controller '
        'once the sheet lets go', (tester) async {
      final semantics = tester.ensureSemantics();
      server.playlists[1] = server.playlists[1].copyWith(shareId: shareIdA);
      await open(tester, showing: showing);
      await openMenu(tester);
      await tester.tap(find.text('停止分享'));
      await settlePage(tester);
      await leave(tester);
      showing.value = true;
      await settlePage(tester);

      await tester.tap(find.widgetWithText(PillButton, '停止分享'));
      await settlePage(tester);

      expect(server.calls, contains('unshare pl-1'));
      expect(container.exists(myPlaylistsControllerProvider), isTrue);
      expect(container.exists(myPlaylistControllerProvider('pl-1')), isTrue);
      await openMenu(tester);
      expect(find.text('分享'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('still deletes, and goes nowhere', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, showing: showing);
      await openMenu(tester);
      await tester.tap(find.text('删除'));
      await settlePage(tester);

      await leave(tester);
      await tester.tap(find.widgetWithText(PillButton, '删除'));
      await settlePage(tester);

      expect(tester.takeException(), isNull);
      expect(server.calls, contains('delete pl-1'));
      expect(deleted, 0);
      semantics.dispose();
    });

    testWidgets('still removes the selected songs', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, showing: showing);
      await tester.tap(find.text('选择'));
      await settlePage(tester);
      await tester.tap(find.bySemanticsLabel('歌c'));
      await tester.tap(find.bySemanticsLabel('歌d'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('把选中的歌移出这个歌单'));
      await settlePage(tester);

      await leave(tester);
      expect(container.exists(myPlaylistControllerProvider('pl-1')), isTrue);
      await tester.tap(find.widgetWithText(PillButton, '移出'));
      await settlePage(tester);

      expect(tester.takeException(), isNull);
      expect(server.calls, contains('remove pl-1 netease:c,netease:d'));
      expect(notices, isEmpty);
      semantics.dispose();
    });
  });

  testWidgets('with reduced motion the selection bar appears at once', (
    tester,
  ) async {
    await open(tester, reduceMotion: true);

    await tester.tap(find.text('选择'));
    await tester.pump();
    final shown = tester.getRect(find.text('移到最前'));
    await settlePage(tester);

    expect(tester.getRect(find.text('移到最前')), shown);
  });

  testWidgets('without reduced motion the selection bar slides in', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('选择'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final moving = tester.getRect(find.text('移到最前'));
    await settlePage(tester);

    expect(tester.getRect(find.text('移到最前')), isNot(moving));
  });

  testWidgets('at twice the text size nothing overflows, also while '
      'selecting', (tester) async {
    await open(tester, textScaler: const TextScaler.linear(2));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('选择'));
    await settlePage(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('全选'));
    await settlePage(tester);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [2.0, 3.0]) {
    testWidgets('at 320 dp and ${scale}x text everything selected fits', (
      tester,
    ) async {
      await open(
        tester,
        size: const Size(320, 760),
        textScaler: TextScaler.linear(scale),
      );
      await tester.tap(find.text('选择'));
      await settlePage(tester);
      await tester.tap(find.text('全选'));
      await settlePage(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('已选 4 首'), findsOneWidget);
      expect(find.text('取消全选').hitTestable(), findsOneWidget);
      expect(find.bySemanticsLabel('退出选择').hitTestable(), findsOneWidget);
    });
  }

  for (final scale in [2.0, 3.0]) {
    testWidgets('at 320 dp and ${scale}x text an unknown pick result leaves '
        'room for the menu', (tester) async {
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
      await tester.scrollUntilVisible(
        find.text('结果未知'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('结果未知').hitTestable(), findsOneWidget);
      // 点歌按钮不盖住封面和歌名。
      expect(
        tester.getRect(find.byIcon(Icons.question_mark_rounded)).left,
        greaterThan(tester.getRect(find.text('歌a')).left),
      );
      final menu = find.bySemanticsLabel('《歌a》的更多操作');
      expect(menu.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(menu).right,
        lessThanOrEqualTo(tester.getSize(find.byType(MaterialApp)).width),
      );
    });
  }

  for (final (state, id, text) in [
    ('an empty', 'pl-1', '这个歌单还是空的'),
    ('a gone', 'missing', '这个歌单不存在了'),
  ]) {
    testWidgets('at twice the text size $state playlist fits', (tester) async {
      server.contents['pl-1'] = [];
      await open(tester, id: id, textScaler: const TextScaler.linear(2));

      expect(find.text(text), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
