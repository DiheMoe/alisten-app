import 'dart:async';

import 'package:alisten/core/realtime/room_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../search_test_doubles.dart';

void main() {
  List<Object?> pagesAsked(SearchPage page, String type) => [
    for (final request in page.transport.requests)
      if (request['type'] == type)
        (request['data']! as Map<String, Object?>)['page'],
  ];

  List<Object?> songPages(SearchPage page) => pagesAsked(page, 'search.tracks');

  // 每页 20 首；第 [gone] 页起平台不再给结果。
  void serveSongs(
    SearchPage page, {
    int total = 4321,
    int? gone,
    bool Function(int)? refuse,
    Future<void> Function(int)? hold,
  }) {
    page.transport.requestHandler = (type, data) async {
      if (type != 'search.tracks') return page.transport.responses[type]!;
      final number = data['page']! as int;
      await hold?.call(number);
      if (refuse?.call(number) ?? false) {
        throw const RoomRequestException(
          code: 'RATE_LIMITED',
          message: '搜索过于频繁，请稍后再试。',
          outcome: RoomRequestOutcome.failed,
        );
      }
      return tracksAnswer([
        if (gone == null || number < gone)
          for (var i = 0; i < 20; i++) 'p$number-$i',
      ], total: total);
    };
  }

  Future<void> openSongs(SearchPage page) async {
    await page.search('晴天');
    await page.tester.tap(find.text('歌曲').first);
    await page.settle();
  }

  Future<void> scrollToEnd(SearchPage page) async {
    await page.tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
    );
    await page.settle();
  }

  double scrolled(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;

  Future<void> turn(SearchPage page, String arrow) async {
    await scrollToEnd(page);
    await page.tester.tap(find.bySemanticsLabel(arrow));
    await page.settle();
  }

  testWidgets('songs are shown a page at a time, turned by the arrows at the '
      'end of the list, and each page starts from its top', (tester) async {
    final page = await SearchPage.open(tester);
    serveSongs(page);

    await openSongs(page);
    await scrollToEnd(page);
    expect(songPages(page), [1]);
    expect(find.text('1 / 217'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('下一页'));
    await page.settle();
    expect(songPages(page), [1, 2]);
    expect(find.text('p2-0'), findsOneWidget);
    expect(find.text('p1-0', skipOffstage: false), findsNothing);
    expect(scrolled(tester), 0);

    await scrollToEnd(page);
    expect(find.text('2 / 217'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('上一页'));
    await page.settle();
    expect(songPages(page), [1, 2]);
    expect(find.text('p1-0'), findsOneWidget);
    expect(scrolled(tester), 0);
  });

  testWidgets('the first page has no way back and the last no way on', (
    tester,
  ) async {
    final page = await SearchPage.open(tester);
    serveSongs(page, total: 40);
    await openSongs(page);
    await scrollToEnd(page);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('上一页'));
    await page.settle();
    expect(songPages(page), [1]);

    await tester.tap(find.bySemanticsLabel('下一页'));
    await page.settle();
    await scrollToEnd(page);
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('下一页'));
    await page.settle();
    expect(songPages(page), [1, 2]);
  });

  testWidgets('a search of one page shows no page numbers', (tester) async {
    final page = await SearchPage.open(tester);
    serveSongs(page, total: 20);

    await openSongs(page);
    await scrollToEnd(page);

    expect(find.text('p1-19'), findsOneWidget);
    expect(find.text('1 / 1'), findsNothing);
    expect(find.bySemanticsLabel('下一页'), findsNothing);
  });

  testWidgets('while a page is on its way the page shown stays and the '
      'arrow pressed shows progress; the old page leaves only once the new '
      'one is there', (tester) async {
    final page = await SearchPage.open(tester);
    final arrived = Completer<void>();
    serveSongs(
      page,
      hold: (number) async {
        if (number == 2) await arrived.future;
      },
    );
    await openSongs(page);
    await scrollToEnd(page);

    await tester.tap(find.bySemanticsLabel('下一页'));
    await page.settle();
    expect(find.bySemanticsLabel('正在翻页'), findsOneWidget);
    expect(find.bySemanticsLabel('下一页'), findsNothing);
    expect(find.text('p1-19'), findsOneWidget);
    expect(find.text('1 / 217'), findsOneWidget);

    arrived.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('p1-19'), findsOneWidget);
    expect(find.text('p2-0', skipOffstage: false), findsNothing);

    await page.settle();
    expect(find.text('p2-0'), findsOneWidget);
    expect(find.text('p1-19', skipOffstage: false), findsNothing);
    expect(find.bySemanticsLabel('正在翻页'), findsNothing);
  });

  testWidgets('a page refused for searching too often leaves the page shown '
      'with the reason, and 重试 asks for that page again', (tester) async {
    final page = await SearchPage.open(tester);
    var refusing = true;
    serveSongs(page, refuse: (number) => number == 2 && refusing);
    await openSongs(page);

    await turn(page, '下一页');
    await scrollToEnd(page);
    expect(find.text('搜索过于频繁，请稍后再试。'), findsOneWidget);
    expect(find.text('p1-19'), findsOneWidget);
    expect(find.text('1 / 217'), findsOneWidget);
    expect(songPages(page), [1, 2]);

    refusing = false;
    await tester.tap(find.text('重试'));
    await page.settle();
    expect(songPages(page), [1, 2, 2]);
    expect(find.text('p2-0'), findsOneWidget);
    expect(find.text('搜索过于频繁，请稍后再试。'), findsNothing);
  });

  testWidgets('a page the platform does not give says 已经是最后一页, and the '
      'count stops at the page shown', (tester) async {
    final page = await SearchPage.open(tester);
    serveSongs(page, gone: 3);
    await openSongs(page);
    await turn(page, '下一页');

    await turn(page, '下一页');
    expect(find.text('已经是最后一页'), findsOneWidget);
    expect(find.text('p2-0', skipOffstage: false), findsOneWidget);

    await scrollToEnd(page);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('playlists are turned a page at a time too', (tester) async {
    final page = await SearchPage.open(tester);
    page.transport.requestHandler = (type, data) async {
      if (type != 'search.playlists') return page.transport.responses[type]!;
      final number = data['page']! as int;
      return {
        'items': [for (var i = 0; i < 20; i++) playlistJson('list-$number-$i')],
        'total': 4321,
      };
    };
    await page.search('晴天');
    await tester.tap(find.text('歌单').first);
    await page.settle();

    await turn(page, '下一页');
    expect(pagesAsked(page, 'search.playlists'), [1, 2]);
    expect(find.text('list-2-0'), findsOneWidget);
    expect(find.text('list-1-0', skipOffstage: false), findsNothing);
    expect(scrolled(tester), 0);
  });
}
