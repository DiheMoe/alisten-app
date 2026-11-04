import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../search_test_doubles.dart';

void main() {
  testWidgets('going back from a playlist returns to the search as it '
      'was', (tester) async {
    final semantics = tester.ensureSemantics();
    final page = await SearchPage.open(tester);
    page.transport.responses['search.playlists'] = {
      'items': [playlistJson('1001', name: '华语流行')],
      'total': 1,
    };
    await tester.tap(find.text('网易云'));
    await page.settle();
    await page.search('晴天');
    await tester.tap(find.text('歌单').first);
    await page.settle();

    await tester.tap(find.text('华语流行'));
    await page.settle();
    expect(page.router.state.uri.path, '/r/listen/playlists/netease/1001');
    expect(find.text('song-0'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('返回'));
    await page.settle();
    expect(page.router.state.uri.path, '/r/listen/search');
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.controller.text, '晴天');
    expect(find.text('华语流行'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a search field the user tapped does not take the keyboard '
      'again on the way back from a playlist', (tester) async {
    final page = await SearchPage.open(tester);
    bool focused() => tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode
        .hasFocus;
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    expect(focused(), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    page.router.push('/r/listen/playlists/netease/1001').ignore();
    await page.settle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('song-0'), findsOneWidget);

    page.router.pop();
    await page.settle();
    await tester.pump(const Duration(seconds: 1));
    expect(page.router.state.uri.path, '/r/listen/search');
    expect(focused(), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('an empty playlist says so instead of a page count', (
    tester,
  ) async {
    final page = await SearchPage.open(tester);
    page.transport.responses['playlist.tracks'] = {
      'items': <Object?>[],
      'total': 0,
    };

    page.router.push('/r/listen/playlists/netease/1001').ignore();
    await page.settle();

    expect(find.text('这个歌单里还没有歌'), findsOneWidget);
    expect(find.text('1 / 1'), findsNothing);
  });

  testWidgets('a playlist says why its songs cannot be picked while the room '
      'is not connected', (tester) async {
    final page = await SearchPage.open(tester);
    page.router.push('/r/listen/playlists/netease/1001').ignore();
    await page.settle();
    expect(find.text('song-0'), findsOneWidget);
    expect(find.text('连接后可点歌'), findsNothing);

    page.transport.disconnect();
    await page.settle();

    expect(find.text('连接后可点歌'), findsOneWidget);
    expect(find.text('song-0'), findsOneWidget);
    unawaited(page.transport.stop());
  });
}
