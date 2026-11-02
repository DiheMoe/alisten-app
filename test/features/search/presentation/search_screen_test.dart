import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../search_test_doubles.dart';

void main() {
  testWidgets('a song found is sent once, says it was picked and is counted', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final page = await SearchPage.open(tester);
    page.transport.responses['search.tracks'] = tracksAnswer(['晴天', '七里香']);
    page.holdAdds();

    await page.search('晴天');
    expect(find.text('最佳匹配'), findsOneWidget);
    final pick = find.bySemanticsLabel('点歌《晴天》');
    expect(pick, findsOneWidget);

    await tester.tap(pick);
    await tester.pump();
    expect(page.adds, 1);
    expect(tester.getSemantics(pick).value, '进行中');

    await tester.tap(pick, warnIfMissed: false);
    await tester.pump();
    expect(page.adds, 1, reason: 'a song on its way is not sent again');

    page.answerAdd('晴天');
    await page.settle();
    expect(page.adds, 1);
    expect(tester.getSemantics(pick).value, '已点');
    expect(find.text('已点'), findsOneWidget);
    expect(find.text('已点 1 首'), findsOneWidget);
    expect(find.text('已点歌《晴天》'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a song whose answer is lost shows a question mark and says '
      'the result is unknown', (tester) async {
    final semantics = tester.ensureSemantics();
    final page = await SearchPage.open(tester);
    page.transport.responses['search.tracks'] = tracksAnswer(['晴天']);
    page.holdAdds();
    await page.search('晴天');

    final pick = find.bySemanticsLabel('点歌《晴天》');
    await tester.tap(pick);
    await tester.pump();
    page.loseAdd();
    await page.settle();

    expect(find.byIcon(Icons.question_mark_rounded), findsOneWidget);
    expect(find.text('结果未知'), findsOneWidget);
    expect(tester.getSemantics(pick).value, '结果未知');
    expect(find.text('结果未知，已重新同步'), findsOneWidget);
    expect(find.text('已点 1 首'), findsNothing);
    semantics.dispose();
  });

  testWidgets('QQ Music offers no playlists, NetEase does', (tester) async {
    final page = await SearchPage.open(tester);

    await page.search('晴天');
    expect(find.text('最佳匹配'), findsOneWidget);
    expect(find.text('歌单'), findsNothing);
    expect(
      page.transport.requests.where((r) => r['type'] == 'search.playlists'),
      isEmpty,
    );

    await tester.tap(find.text('网易云'));
    await page.settle();
    expect(find.text('歌单'), findsWidgets);
  });

  testWidgets('a temporary room offers to pick a Bilibili link and no other', (
    tester,
  ) async {
    final page = await SearchPage.open(tester);

    await tester.enterText(find.byType(EditableText), 'https://b23.tv/abc');
    await page.settle();
    expect(find.text('点这条链接'), findsOneWidget);

    await tester.enterText(
      find.byType(EditableText),
      'https://evil-bilibili.com/x',
    );
    await page.settle();
    expect(find.text('点这条链接'), findsNothing);
    expect(find.text('临时房间只能点 B 站链接'), findsOneWidget);
  });

  testWidgets('a search that finds nothing says so', (tester) async {
    final page = await SearchPage.open(tester);
    page.transport.responses['search.tracks'] = tracksAnswer([]);

    await page.search('没有这首歌');

    expect(find.text('没有找到“没有这首歌”'), findsOneWidget);
    expect(find.text('1 / 1'), findsNothing);
    expect(find.text('最佳匹配'), findsNothing);
  });
}
