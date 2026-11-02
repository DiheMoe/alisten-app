import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../search_test_doubles.dart';
import '../share_test_doubles.dart';

const _clipboardHeading = '点剪贴板里的链接';

List<(Object?, Object?)> _picked(SearchPage page) {
  return [
    for (final request in page.transport.requests)
      if (request['type'] == 'queue.add')
        switch (request['data']) {
          {'track': {'source': final source, 'id': final id}} => (source, id),
          _ => (null, null),
        },
  ];
}

Future<void> _reopen(SearchPage page) async {
  page.router.go('/r/listen');
  await page.settle();
  page.router.go('/r/listen/search');
  await page.settle();
}

void main() {
  testWidgets('a song link on the clipboard is offered at the top and picked '
      'as that song', (tester) async {
    final page = await SearchPage.open(
      tester,
      clipboard: FakeClipboardSource(neteaseShareText),
    );
    page.holdAdds();

    expect(find.text(_clipboardHeading), findsOneWidget);
    expect(find.text('网易云'), findsWidgets);
    expect(find.text('晴天'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('点歌《晴天》'));
    await tester.pump();
    expect(_picked(page), [('netease', '186016')]);

    page.answerAdd('晴天');
    await page.settle();
    expect(find.text('已点歌《晴天》'), findsOneWidget);
    expect(find.text(_clipboardHeading), findsNothing);
  });

  testWidgets('what the clipboard held is offered once, and read once until '
      'it changes', (tester) async {
    final clipboard = FakeClipboardSource(neteaseShareText);
    final page = await SearchPage.open(tester, clipboard: clipboard);
    expect(find.text(_clipboardHeading), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('不点这条链接'));
    await page.settle();
    expect(find.text(_clipboardHeading), findsNothing);

    await _reopen(page);
    expect(find.text(_clipboardHeading), findsNothing);
    expect(clipboard.reads, 1);

    clipboard.copy('https://b23.tv/xyz');
    await _reopen(page);
    expect(find.text(_clipboardHeading), findsOneWidget);
    expect(find.text('B 站'), findsOneWidget);
  });

  testWidgets('a website link on the clipboard is not offered in a temporary '
      'room', (tester) async {
    await SearchPage.open(
      tester,
      clipboard: FakeClipboardSource('https://example.com/a.mp3'),
    );

    expect(find.text(_clipboardHeading), findsNothing);
  });

  testWidgets('a clipboard that carries no stamp, as on iOS, is never '
      'read', (tester) async {
    final clipboard = FakeClipboardSource(neteaseShareText)..stamped = false;

    await SearchPage.open(tester, clipboard: clipboard);

    expect(clipboard.reads, 0);
    expect(find.text(_clipboardHeading), findsNothing);
  });

  testWidgets('a link typed shows what it names at once, with nothing to '
      'wait for', (tester) async {
    await SearchPage.open(tester);

    await tester.enterText(
      find.byType(EditableText),
      'https://music.163.com/song?id=186016',
    );
    await tester.pump();

    expect(find.text('点这条链接'), findsOneWidget);
    expect(find.text('正在识别链接'), findsNothing);
    expect(find.bySemanticsLabel('点这首歌'), findsOneWidget);
  });

  testWidgets('a NetEase song link typed in the field is picked as the '
      'NetEase song, not as a link', (tester) async {
    final page = await SearchPage.open(tester);

    await tester.enterText(
      find.byType(EditableText),
      'https://music.163.com/song?id=186016',
    );
    await page.settle();
    expect(find.text('点这条链接'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('点这首歌'));
    await page.settle();
    expect(_picked(page), [('netease', '186016')]);
  });

  testWidgets('a NetEase playlist link typed in the field says only songs '
      'can be picked', (tester) async {
    final page = await SearchPage.open(tester);

    await tester.enterText(
      find.byType(EditableText),
      'https://music.163.com/#/playlist?id=1',
    );
    await page.settle();

    expect(find.text('只支持单曲链接'), findsOneWidget);
    expect(find.text('点这条链接'), findsNothing);
    expect(_picked(page), isEmpty);
  });
}
