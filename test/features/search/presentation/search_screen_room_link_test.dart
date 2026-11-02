import 'dart:async';

import 'package:alisten/features/search/index.dart' show PickControl;
import 'package:alisten/features/server/index.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../server/server_test_doubles.dart' show FakeServerProbe;
import '../search_test_doubles.dart';
import '../share_test_doubles.dart';

const _roomLinkText = '这是房间链接，不能用来点歌。';
const _unrecognized = '没能识别这个链接';
// 点歌页只在房间内，进入另一个房间即离开当前房间。
const _enter = '离开当前房间并进入';

void main() {
  Future<void> type(SearchPage page, String text) async {
    await page.tester.enterText(find.byType(EditableText), text);
    await page.tester.pump();
  }

  testWidgets('a room link typed is told as one, never offered to pick, and '
      'stays told behind and after the invite', (tester) async {
    final probe = FakeServerProbe()
      ..gate = Completer()
      ..siteResults['https://new.example.org'] = const ProbeSucceeded(
        origin: 'https://new.example.org',
        brandName: '新站',
      );
    final page = await SearchPage.open(tester, probe: probe);

    await type(page, 'https://new.example.org/r/party');
    expect(find.text('正在识别链接'), findsOneWidget);
    expect(find.text('点这条链接'), findsNothing);
    expect(find.byType(PickControl), findsNothing);

    await page.settle();
    expect(probe.siteProbed, hasLength(1));
    expect(find.text('正在识别链接'), findsOneWidget);
    expect(find.byType(PickControl), findsNothing);

    probe.gate!.complete();
    await page.settle();
    expect(find.text('添加 新站 并进入房间？'), findsOneWidget);
    expect(find.text(_roomLinkText), findsOneWidget);
    expect(find.text(_unrecognized), findsNothing);

    await tester.tap(find.text('取消'));
    await page.settle();
    expect(find.text('添加 新站 并进入房间？'), findsNothing);
    expect(find.text(_roomLinkText), findsOneWidget);
    expect(find.text(_unrecognized), findsNothing);
  });

  testWidgets('the link of the room in use typed is told as a room link', (
    tester,
  ) async {
    final page = await SearchPage.open(tester);

    await type(page, 'https://livehouse.dihe.moe/r/listen');
    await page.settle();

    expect(find.text(_roomLinkText), findsOneWidget);
    expect(find.text(_unrecognized), findsNothing);
    expect(page.router.state.uri.path, '/r/listen/search');
  });

  testWidgets('another room of this server typed is entered only once its '
      'card is tapped', (tester) async {
    final page = await SearchPage.open(tester);

    final semantics = tester.ensureSemantics();
    await type(page, 'https://livehouse.dihe.moe/r/other');
    expect(find.text('正在识别链接'), findsOneWidget);
    expect(find.text('点这条链接'), findsNothing);

    await page.settle();
    await page.settle();

    expect(page.router.state.uri.path, '/r/listen/search');
    expect(find.text(_enter), findsOneWidget);
    expect(find.bySemanticsLabel(_enter), findsOneWidget);
    expect(find.text('进入这个房间'), findsNothing);
    expect(find.text(_unrecognized), findsNothing);
    semantics.dispose();

    await tester.tap(find.text(_enter));
    await page.settle();
    expect(page.router.state.uri.path, '/r/other');
  });

  testWidgets('another room of this server on the clipboard is entered only '
      'once its card is tapped', (tester) async {
    final page = await SearchPage.open(
      tester,
      clipboard: FakeClipboardSource('https://livehouse.dihe.moe/r/other'),
    );
    await page.settle();

    expect(page.router.state.uri.path, '/r/listen/search');
    expect(find.text('剪贴板里的房间链接'), findsOneWidget);
    expect(find.text(_enter), findsOneWidget);

    await tester.tap(find.text(_enter));
    await page.settle();
    expect(page.router.state.uri.path, '/r/other');
  });
}
