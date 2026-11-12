import 'dart:async';

import 'package:alisten/domain/playlist/playlist_date.dart';
import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/playlist/playlist_sort.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playlists/index.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playlists_page_harness.dart';
import '../playlists_test_doubles.dart';

void main() {
  late FakePlaylistApi server;
  late FakePlaylistFileSource files;
  late List<String> opened;
  late List<(ToastKind, String)> notices;
  late List<Duration?> noticeDurations;
  late int accountOpened;

  void notice(ToastKind kind, String text, {Duration? duration}) {
    notices.add((kind, text));
    noticeDurations.add(duration);
  }

  setUp(() {
    opened = [];
    notices = [];
    noticeDurations = [];
    accountOpened = 0;
    files = FakePlaylistFileSource();
    server = FakePlaylistApi()
      ..playlists.addAll([
        favoritesPlaylist,
        playlist('pl-1', name: '夜跑', trackCount: 3, updatedAtMs: 5),
        playlist('pl-2', name: '晨跑', trackCount: 9, updatedAtMs: 9),
      ]);
  });

  Future<ProviderContainer> open(
    WidgetTester tester, {
    bool signedIn = true,
    TextScaler textScaler = TextScaler.noScaling,
    Size size = const Size(360, 780),
  }) {
    return pumpPlaylistsPage(
      tester,
      MyPlaylistsScreen(
        onOpenPlaylist: opened.add,
        onOpenAccount: () => accountOpened++,
        onNotice: notice,
      ),
      playlists: server,
      files: files,
      signedIn: signedIn,
      textScaler: textScaler,
      size: size,
    );
  }

  Future<void> openLinkSheet(WidgetTester tester) async {
    await tester.tap(find.text('导入'));
    await settlePage(tester);
    await tester.tap(find.text('从链接导入'));
    await settlePage(tester);
  }

  Future<void> enterLink(WidgetTester tester, String link) async {
    await tester.enterText(find.byType(EditableText).first, link);
    await tester.pump();
  }

  void expectUnderFields(WidgetTester tester, String text) {
    expect(find.text(text), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(text)).dy,
      greaterThan(tester.getBottomLeft(find.byType(EditableText).last).dy),
    );
  }

  testWidgets('a guest is told what playlists are for and sent to the '
      'account settings', (tester) async {
    await open(tester, signedIn: false);

    expect(find.text('收藏你喜欢的歌'), findsOneWidget);
    expect(find.text('注册账号之后，就能收藏歌曲、建自己的歌单。'), findsOneWidget);
    await tester.tap(find.text('去账号设置'));
    expect(accountOpened, 1);
    expect(server.calls, isEmpty);
  });

  testWidgets('loading is announced until the list arrives', (tester) async {
    final semantics = tester.ensureSemantics();
    final reply = server.hold('listMine');
    await open(tester);

    expect(find.bySemanticsLabel('正在加载歌单'), findsOneWidget);
    expect(find.text('我的歌单'), findsOneWidget);

    reply.complete();
    await settlePage(tester);
    expect(find.text('3 个歌单'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a failed read offers a retry', (tester) async {
    server.failNext('listMine', networkError);
    await open(tester);

    expect(find.text('读取失败：${networkError.message}'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await settlePage(tester);
    expect(find.text('3 个歌单'), findsOneWidget);
  });

  testWidgets('favorites come first and have no menu; a card opens its '
      'playlist', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    expect(find.text('3 个歌单'), findsOneWidget);
    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    double left(String name) => tester.getTopLeft(find.text(name)).dx;
    expect(top('我喜欢'), lessThanOrEqualTo(top('晨跑')));
    expect(left('我喜欢'), lessThan(left('晨跑')), reason: 'two columns');
    expect(find.bySemanticsLabel('“我喜欢”的更多操作'), findsNothing);
    expect(find.bySemanticsLabel('“夜跑”的更多操作'), findsOneWidget);

    await tester.tap(find.text('夜跑'));
    expect(opened, ['pl-1']);
    semantics.dispose();
  });

  testWidgets('a card or a row is read as one button with the name and its '
      'facts', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    final label = '夜跑，3 首 · ${formatPlaylistDate(5, testNowMs)}';

    for (final view in ['网格', '列表']) {
      await tester.tap(find.bySemanticsLabel(view));
      await settlePage(tester);
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(label: label, isButton: true),
        reason: view,
      );
      expect(find.bySemanticsLabel('夜跑'), findsNothing, reason: view);
    }
    semantics.dispose();
  });

  testWidgets('the view icons are named and their choice announced; the list '
      'view is kept as the preference', (tester) async {
    final semantics = tester.ensureSemantics();
    final container = await open(tester);
    Matcher choice({required bool selected}) => isSemantics(
      isButton: true,
      isSelected: selected,
      isInMutuallyExclusiveGroup: true,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('网格')),
      choice(selected: true),
    );

    await tester.tap(find.bySemanticsLabel('列表'));
    await settlePage(tester);

    expect(
      tester.getSemantics(find.bySemanticsLabel('列表')),
      choice(selected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('网格')),
      choice(selected: false),
    );
    expect(container.read(playlistViewProvider).view, PlaylistView.list);
    expect(
      container.read(playlistViewStoreProvider).read().view,
      PlaylistView.list,
    );
    double left(String name) => tester.getTopLeft(find.text(name)).dx;
    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(left('晨跑'), left('夜跑'), reason: 'one column');
    expect(top('晨跑'), lessThan(top('夜跑')));
    semantics.dispose();
  });

  for (final size in const [Size(320, 780), Size(360, 780), Size(408, 900)]) {
    testWidgets('at ${size.width.round()} dp the view switch sits on the left '
        'and the sort key with its direction on the right of one row', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await open(tester, size: size);

      final grid = find.bySemanticsLabel('网格');
      final list = find.bySemanticsLabel('列表');
      final sortKey = find.bySemanticsLabel('排序方式：更新时间');
      final direction = find.bySemanticsLabel('最新在前');
      final row = tester.getCenter(grid).dy;
      for (final control in [list, sortKey, direction]) {
        expect(
          tester.getCenter(control).dy,
          moreOrLessEquals(row, epsilon: 2),
          reason: control.describeMatch(Plurality.one),
        );
      }
      expect(
        tester.getTopLeft(grid).dx,
        moreOrLessEquals(AlistenSpacing.page, epsilon: 0.5),
      );
      expect(
        tester.getTopRight(list).dx,
        lessThan(tester.getTopLeft(sortKey).dx),
      );
      expect(
        tester.getTopRight(sortKey).dx,
        lessThanOrEqualTo(tester.getTopLeft(direction).dx),
      );
      expect(
        tester.getTopRight(direction).dx,
        moreOrLessEquals(size.width - AlistenSpacing.page, epsilon: 0.5),
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('the sort menu and the direction are named for a screen '
      'reader; a new key starts with its own direction', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    final sortButton = find.bySemanticsLabel('排序方式：更新时间');
    expect(
      tester.getSemantics(sortButton),
      isSemantics(isButton: true, hasExpandedState: true, isExpanded: false),
    );
    expect(find.bySemanticsLabel('最新在前'), findsOneWidget);

    await tester.tap(sortButton);
    await settlePage(tester);
    expect(
      tester.getSemantics(sortButton),
      isSemantics(hasExpandedState: true, isExpanded: true),
    );
    await tester.tap(find.text('名称'));
    await settlePage(tester);

    expect(
      tester.getSemantics(find.bySemanticsLabel('排序方式：名称')),
      isSemantics(hasExpandedState: true, isExpanded: false),
    );
    expect(find.bySemanticsLabel('A–Z'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('A–Z'));
    await settlePage(tester);
    expect(find.bySemanticsLabel('Z–A'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a playlist is renamed and deleted from its menu', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    await tester.tap(find.bySemanticsLabel('“夜跑”的更多操作'));
    await settlePage(tester);
    await tester.tap(find.text('重命名'));
    await settlePage(tester);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '夜跑',
    );
    expect(find.text('取消'), findsNothing);
    await tester.enterText(find.byType(EditableText), '晚跑');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await settlePage(tester);
    expect(server.calls, contains('rename pl-1 晚跑'));
    expect(find.text('晚跑'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('“晚跑”的更多操作'));
    await settlePage(tester);
    await tester.tap(find.text('删除'));
    await settlePage(tester);
    expect(find.text('删除歌单'), findsOneWidget);
    expect(find.text('删除“晚跑”之后，里面的歌也一起删除。'), findsOneWidget);
    await tester.tap(find.widgetWithText(PillButton, '删除'));
    await settlePage(tester);
    expect(server.calls, contains('delete pl-1'));
    expect(find.text('晚跑'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a server switch closes the rename sheet', (tester) async {
    final container = await open(tester);
    await tester.tap(find.bySemanticsLabel('“夜跑”的更多操作'));
    await settlePage(tester);
    await tester.tap(find.text('重命名'));
    await settlePage(tester);
    expect(find.byType(EditableText), findsOneWidget);

    unawaited(
      container
          .read(identityControllerProvider.notifier)
          .resetForServerChange(),
    );
    await settlePage(tester);

    expect(find.byType(EditableText), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a server switch closes the link sheet', (tester) async {
    final container = await open(tester);
    await openLinkSheet(tester);

    unawaited(
      container
          .read(identityControllerProvider.notifier)
          .resetForServerChange(),
    );
    await settlePage(tester);

    expect(find.text('歌单链接'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new playlist shows up in the list', (tester) async {
    await open(tester);

    await tester.tap(find.widgetWithText(PillButton, '新建歌单'));
    await settlePage(tester);
    await tester.enterText(find.byType(EditableText), '散步');
    await tester.pump();
    await tester.tap(find.text('创建'));
    await settlePage(tester);

    expect(find.text('散步'), findsOneWidget);
    expect(find.text('4 个歌单'), findsOneWidget);
    expect(notices, isEmpty);
  });

  Future<void> cover(WidgetTester tester) async {
    unawaited(
      showSheetPanel<void>(
        tester.element(find.byType(EditableText).first),
        builder: (_) => const Text('盖在上面'),
      ),
    );
    await settlePage(tester);
  }

  testWidgets('a create that answers under another sheet closes only its '
      'own sheet', (tester) async {
    await open(tester);
    await tester.tap(find.widgetWithText(PillButton, '新建歌单'));
    await settlePage(tester);
    final answer = server.hold('create');
    await tester.enterText(find.byType(EditableText), '散步');
    await tester.pump();
    await tester.tap(find.text('创建'));
    await tester.pump();
    await cover(tester);

    answer.complete();
    await settlePage(tester);

    expect(find.text('盖在上面'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a file is imported with a notice that tells a cut', (
    tester,
  ) async {
    files.next = const PlaylistFile(
      name: '旧歌单',
      tracks: [
        PlaylistFileTrack(
          track: Track(source: TrackSource.qq, id: '1'),
          title: '晴天',
          durationMs: 0,
        ),
      ],
      truncated: true,
    );
    await open(tester);

    await tester.tap(find.text('导入'));
    await settlePage(tester);
    await tester.tap(find.text('从文件导入'));
    await settlePage(tester);

    expect(notices, [
      (ToastKind.success, '已导入 1 首到“旧歌单”。文件里超过 1000 首，只导入了前 1000 首。'),
    ]);
    expect(noticeDurations, [
      AlistenDurations.longToast,
    ], reason: 'like Web, the long notice stays longer');
    expect(find.text('旧歌单'), findsOneWidget);
    expect(opened, isEmpty, reason: 'like Web, the new playlist is not opened');
  });

  testWidgets('while a file is imported the button is busy and cannot be '
      'pressed', (tester) async {
    files.next = const PlaylistFile(
      name: '旧歌单',
      tracks: [
        PlaylistFileTrack(
          track: Track(source: TrackSource.qq, id: '1'),
          title: '晴天',
          durationMs: 0,
        ),
      ],
      truncated: false,
    );
    final reply = server.hold('importFile');
    await open(tester);

    await tester.tap(find.text('导入'));
    await settlePage(tester);
    await tester.tap(find.text('从文件导入'));
    await settlePage(tester);

    expect(find.text('正在导入…'), findsOneWidget);
    await tester.tap(find.text('正在导入…'));
    await settlePage(tester);
    expect(find.text('从文件导入'), findsNothing, reason: 'no menu while busy');

    reply.complete();
    await settlePage(tester);
    expect(notices, [(ToastKind.success, '已导入 1 首到“旧歌单”')]);
    expect(noticeDurations, [null], reason: 'a short notice keeps the default');
    expect(find.text('导入'), findsOneWidget);
    expect(files.picks, 1);
  });

  testWidgets('a file that is not a playlist is told and nothing is sent', (
    tester,
  ) async {
    files.next = const PlaylistFileProblem('这个文件不是导出的歌单。');
    await open(tester);

    await tester.tap(find.text('导入'));
    await settlePage(tester);
    await tester.tap(find.text('从文件导入'));
    await settlePage(tester);

    expect(notices, [(ToastKind.failure, '这个文件不是导出的歌单。')]);
    expect(server.count('importFile'), 0);
  });

  testWidgets('a cancelled pick does nothing', (tester) async {
    await open(tester);

    await tester.tap(find.text('导入'));
    await settlePage(tester);
    await tester.tap(find.text('从文件导入'));
    await settlePage(tester);

    expect(files.picks, 1);
    expect(notices, isEmpty);
    expect(server.count('importFile'), 0);
    expect(find.text('导入'), findsOneWidget);
  });

  for (final (code, serverText, shown) in [
    ('INVALID_ARGUMENT', 'tracks：不合法', '文件里有不符合要求的内容，没有导入。'),
    ('CONFLICT', '最多只能建 50 个歌单', '最多只能建 50 个歌单'),
  ]) {
    testWidgets('a file the server refuses with $code is told', (tester) async {
      files.next = const PlaylistFile(
        name: '旧歌单',
        tracks: [
          PlaylistFileTrack(
            track: Track(source: TrackSource.qq, id: '1'),
            title: '晴天',
            durationMs: 0,
          ),
        ],
        truncated: false,
      );
      server.failNext('importFile', apiError(code, message: serverText));
      await open(tester);

      await tester.tap(find.text('导入'));
      await settlePage(tester);
      await tester.tap(find.text('从文件导入'));
      await settlePage(tester);

      expect(notices, [(ToastKind.failure, shown)]);
      expect(find.text('3 个歌单'), findsOneWidget);
      expect(find.text('导入'), findsOneWidget);
    });
  }

  testWidgets('the import button says whether its menu is open', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    expect(
      tester.getSemantics(find.text('导入')),
      isSemantics(
        label: '导入',
        isButton: true,
        hasExpandedState: true,
        isExpanded: false,
      ),
    );
    await tester.tap(find.text('导入'));
    await settlePage(tester);
    expect(
      tester.getSemantics(find.text('导入')),
      isSemantics(hasExpandedState: true, isExpanded: true),
    );
    semantics.dispose();
  });

  testWidgets('the link sheet does not take focus or raise the keyboard', (
    tester,
  ) async {
    await open(tester);
    await openLinkSheet(tester);

    expect(find.text('歌单链接'), findsOneWidget);
    expect(find.text('粘贴网易云或 QQ 音乐的歌单链接'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).last)
          .controller
          .text,
      '导入的歌单',
    );
    for (final field in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(field.focusNode.hasFocus, isFalse);
    }
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.widgetWithText(PillButton, '取消'));
    await settlePage(tester);
    expect(find.text('歌单链接'), findsNothing);
    expect(opened, isEmpty);
    expect(server.count('resolveLink'), 0);
  });

  testWidgets('a link is imported and its playlist opened', (tester) async {
    await open(tester);

    await openLinkSheet(tester);
    expect(find.text('从链接导入'), findsOneWidget);
    final importButton = find.widgetWithText(PillButton, '导入').last;
    await tester.tap(importButton);
    await tester.pump();
    expect(server.count('resolveLink'), 0, reason: 'no link yet');

    await tester.enterText(
      find.byType(EditableText).first,
      'https://music.163.com/playlist?id=24381616',
    );
    await tester.pump();
    await tester.enterText(find.byType(EditableText).last, ' ');
    await tester.pump();
    await tester.tap(importButton);
    await tester.pump();
    expect(server.count('resolveLink'), 0, reason: 'no name');

    await tester.enterText(find.byType(EditableText).last, '导入的歌单');
    await tester.pump();
    await tester.tap(importButton);
    await settlePage(tester);

    expect(notices, [(ToastKind.success, '已导入 12 首')]);
    expect(opened, ['new-1']);
    expect(server.calls, contains('importPlatform 导入的歌单 netease:24381616'));
    expect(find.text('歌单链接'), findsNothing);
  });

  testWidgets('a link import that answers under another sheet closes only '
      'its own sheet, tells it and opens the playlist', (tester) async {
    await open(tester);
    await openLinkSheet(tester);
    final answer = server.hold('importPlatform');
    await enterLink(tester, 'https://music.163.com/playlist?id=24381616');
    await tester.tap(find.widgetWithText(PillButton, '导入').last);
    await tester.pump();
    await cover(tester);

    answer.complete();
    await settlePage(tester);

    expect(find.text('盖在上面'), findsOneWidget);
    expect(find.text('歌单链接'), findsNothing);
    expect(notices, [(ToastKind.success, '已导入 12 首')]);
    expect(opened, ['new-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a link the server refuses is told under the fields', (
    tester,
  ) async {
    server.failNext(
      'resolveLink',
      apiError('INVALID_ARGUMENT', message: '不是网易云或 QQ 音乐的歌单链接'),
    );
    await open(tester);

    await openLinkSheet(tester);
    await tester.enterText(
      find.byType(EditableText).first,
      'https://example.com',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(PillButton, '导入').last);
    await settlePage(tester);

    expectUnderFields(tester, '不是网易云或 QQ 音乐的歌单链接');
    expect(find.text('歌单链接'), findsOneWidget, reason: 'the sheet stays');
    expect(opened, isEmpty);
  });

  testWidgets('a name the server refuses on a link import is told by the '
      'naming rule', (tester) async {
    server.failNext(
      'importPlatform',
      apiError('INVALID_ARGUMENT', message: 'name：长度必须在 1 到 50 之间'),
    );
    await open(tester);

    await openLinkSheet(tester);
    await enterLink(tester, 'https://music.163.com/playlist?id=24381616');
    await tester.tap(find.widgetWithText(PillButton, '导入').last);
    await settlePage(tester);

    expectUnderFields(tester, '歌单名要 1 到 50 个字。');
    expect(find.textContaining('name：'), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('while a link is sent the sheet is busy, sends once and cannot '
      'be closed; after a failure it works again', (tester) async {
    final reply = server.hold('resolveLink');
    server.failNext(
      'resolveLink',
      apiError('INVALID_ARGUMENT', message: '不是网易云或 QQ 音乐的歌单链接'),
    );
    await open(tester);

    await openLinkSheet(tester);
    await enterLink(tester, 'https://music.163.com/playlist?id=24381616');
    await tester.tap(find.widgetWithText(PillButton, '导入').last);
    await tester.pump();

    expect(find.text('正在导入…'), findsOneWidget);
    await tester.tap(find.text('正在导入…'), warnIfMissed: false);
    await tester.showKeyboard(find.byType(EditableText).last);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(server.count('resolveLink'), 1);
    PillButton cancel() =>
        tester.widget<PillButton>(find.widgetWithText(PillButton, '取消'));
    expect(cancel().onPressed, isNull);

    await tester.binding.handlePopRoute();
    await settlePage(tester);
    await tester.tapAt(const Offset(10, 10));
    await settlePage(tester);
    expect(find.text('歌单链接'), findsOneWidget, reason: 'the sheet stays');

    reply.complete();
    await settlePage(tester);
    expectUnderFields(tester, '不是网易云或 QQ 音乐的歌单链接');
    expect(find.text('正在导入…'), findsNothing);
    expect(cancel().onPressed, isNotNull);

    await tester.tap(find.widgetWithText(PillButton, '导入').last);
    await settlePage(tester);
    expect(server.count('resolveLink'), 2);
    expect(opened, ['new-1']);
    expect(find.text('歌单链接'), findsNothing);
  });

  testWidgets('a link that is too long is told under the fields and not '
      'sent', (tester) async {
    await open(tester);

    await openLinkSheet(tester);
    await enterLink(tester, '歌' * 683);
    await tester.tap(find.widgetWithText(PillButton, '导入').last);
    await settlePage(tester);

    expectUnderFields(tester, '文字太长了，只粘贴歌单的链接或分享文字就好。');
    expect(server.count('resolveLink'), 0);
    expect(find.text('歌单链接'), findsOneWidget, reason: 'the sheet stays');
  });

  for (final (what, error) in [
    ('ends unexpectedly', Exception('boom')),
    ('loses its answer', networkError),
  ]) {
    testWidgets('a link import that $what is unknown: a warning under the '
        'fields, the sheet stays and the list is read again', (tester) async {
      server.failNext('importPlatform', error);
      await open(tester);
      final reads = server.count('listMine');

      await openLinkSheet(tester);
      await enterLink(tester, 'https://music.163.com/playlist?id=24381616');
      await tester.tap(find.widgetWithText(PillButton, '导入').last);
      await settlePage(tester);

      expectUnderFields(tester, '结果未知，已重新读取');
      expect(
        tester.widget<InlineMessage>(find.byType(InlineMessage)).tone,
        StatusTone.warning,
      );
      expect(find.text('歌单链接'), findsOneWidget, reason: 'the sheet stays');
      expect(opened, isEmpty);
      expect(notices, isEmpty);
      expect(server.count('listMine'), reads + 1);
    });
  }

  group('a sheet left open after the page goes away', () {
    // 链接或通知用 router.go 换掉页面时，根导航器上的面板还开着。
    Future<ValueNotifier<bool>> openRemovable(WidgetTester tester) async {
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      final page = MyPlaylistsScreen(
        onOpenPlaylist: opened.add,
        onOpenAccount: () {},
        onNotice: notice,
      );
      await pumpPlaylistsPage(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: shown,
          builder: (_, show, _) => show ? page : const SizedBox(),
        ),
        playlists: server,
        files: files,
      );
      return shown;
    }

    testWidgets('still imports a link, tells it and opens nothing', (
      tester,
    ) async {
      final shown = await openRemovable(tester);
      await openLinkSheet(tester);

      shown.value = false;
      await settlePage(tester);
      expect(find.byType(MyPlaylistsScreen), findsNothing);
      expect(find.text('歌单链接'), findsOneWidget);

      await enterLink(tester, 'https://music.163.com/playlist?id=24381616');
      await tester.tap(find.widgetWithText(PillButton, '导入').last);
      await settlePage(tester);

      expect(notices, [(ToastKind.success, '已导入 12 首')]);
      expect(opened, isEmpty);
      expect(find.text('歌单链接'), findsNothing);
    });

    testWidgets('still deletes a playlist', (tester) async {
      final semantics = tester.ensureSemantics();
      final shown = await openRemovable(tester);
      await tester.tap(find.bySemanticsLabel('“夜跑”的更多操作'));
      await settlePage(tester);
      await tester.tap(find.text('删除'));
      await settlePage(tester);

      shown.value = false;
      await settlePage(tester);
      expect(find.byType(MyPlaylistsScreen), findsNothing);
      await tester.tap(find.widgetWithText(PillButton, '删除'));
      await settlePage(tester);

      expect(tester.takeException(), isNull);
      expect(server.calls, contains('delete pl-1'));
      expect(find.text('删除歌单'), findsNothing);
      expect(notices, isEmpty);
      semantics.dispose();
    });

    testWidgets('still imports a file picked after the page went away', (
      tester,
    ) async {
      final picking = files.held = Completer<void>();
      files.next = const PlaylistFile(
        name: '旧歌单',
        tracks: [
          PlaylistFileTrack(
            track: Track(source: TrackSource.qq, id: '1'),
            title: '晴天',
            durationMs: 0,
          ),
        ],
        truncated: false,
      );
      final shown = await openRemovable(tester);
      await tester.tap(find.text('导入'));
      await settlePage(tester);
      await tester.tap(find.text('从文件导入'));
      await settlePage(tester);

      shown.value = false;
      await settlePage(tester);
      expect(find.byType(MyPlaylistsScreen), findsNothing);
      picking.complete();
      await settlePage(tester);

      expect(tester.takeException(), isNull);
      expect(server.calls, contains('importFile 旧歌单 1'));
      expect(notices, [(ToastKind.success, '已导入 1 首到“旧歌单”')]);
    });

    testWidgets('still creates a playlist', (tester) async {
      final shown = await openRemovable(tester);
      await tester.tap(find.widgetWithText(PillButton, '新建歌单'));
      await settlePage(tester);

      shown.value = false;
      await settlePage(tester);
      expect(find.byType(MyPlaylistsScreen), findsNothing);

      await tester.enterText(find.byType(EditableText), '散步');
      await tester.pump();
      await tester.tap(find.text('创建'));
      await settlePage(tester);

      expect(server.calls, contains('create 散步'));
      expect(find.byType(EditableText), findsNothing, reason: 'closed');
      expect(notices, isEmpty);
    });
  });

  for (final width in [360.0, 320.0]) {
    for (final scale in [2.0, 3.0]) {
      testWidgets('at $width dp and ${scale}x text nothing overflows in the '
          'grid or the list', (tester) async {
        final semantics = tester.ensureSemantics();
        await open(
          tester,
          textScaler: TextScaler.linear(scale),
          size: Size(width, 780),
        );

        final scrollable = find.byType(Scrollable).first;
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('夜跑'),
          200,
          scrollable: scrollable,
        );
        expect(tester.takeException(), isNull);

        final list = find.bySemanticsLabel('列表');
        await tester.scrollUntilVisible(list, -200, scrollable: scrollable);
        await tester.tap(list);
        await settlePage(tester);
        await tester.scrollUntilVisible(
          find.text('夜跑'),
          200,
          scrollable: scrollable,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }
}
