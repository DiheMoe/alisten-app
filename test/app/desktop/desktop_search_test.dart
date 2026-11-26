import 'package:alisten/app/mini_player.dart';
import 'package:alisten/features/search/index.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/search/search_test_doubles.dart';
import '../app_test_harness.dart';

const _wideDesktop = Size(1600, 900);

void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.linux);

  Future<EnteredRoom> openSearch(WidgetTester tester) async {
    final entered = await enterRoom(tester, size: _wideDesktop);
    entered.rooms.last.responses
      ..addAll(defaultSearchAnswers())
      ..['recommend.list'] = {
        'items': List.generate(12, (index) => trackJson('pick-$index')),
      };
    entered.router.go('/r/listen/search');
    await entered.settle();
    await entered.settle();
    return entered;
  }

  Finder inSearch(Finder what) =>
      find.descendant(of: find.byType(SearchScreen), matching: what);

  testWidgets('the search field is ready for typing as the page opens', (
    tester,
  ) async {
    await openSearch(tester);
    final field = inSearch(find.byType(EditableText));
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
  }, variant: desktop);

  testWidgets('on a phone the search page does not raise the keyboard', (
    tester,
  ) async {
    final (:settle, :router, :rooms) = await enterRoom(tester);
    rooms.last.responses.addAll(defaultSearchAnswers());
    router.go('/r/listen/search');
    await settle();
    final field = inSearch(find.byType(EditableText));
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);
  });

  testWidgets('recommendations wrap onto further rows instead of running off '
      'the side', (tester) async {
    await openSearch(tester);
    final page = tester.getRect(find.byType(SearchScreen));
    final covers = inSearch(find.byType(CoverArt));
    expect(covers, findsNWidgets(12));
    final rects = [
      for (final cover in covers.evaluate())
        tester.getRect(find.byWidget(cover.widget)),
    ];
    for (final rect in rects) {
      expect(rect.right, lessThanOrEqualTo(page.right));
      expect(rect.left, greaterThanOrEqualTo(page.left));
    }
    expect({for (final rect in rects) rect.top}.length, greaterThan(1));
  }, variant: desktop);

  testWidgets('the page uses more of a wide window than a phone column', (
    tester,
  ) async {
    final (:settle, router: _, rooms: _) = await openSearch(tester);
    await tester.enterText(inSearch(find.byType(EditableText)), '夜曲');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle();
    final row = tester.getRect(inSearch(find.byType(TrackRow)).first);
    expect(row.width, greaterThan(AlistenSizes.contentMaxWidth));
  }, variant: desktop);

  testWidgets('a right click on a result opens a menu at the pointer that '
      'can pick it', (tester) async {
    final (:settle, router: _, :rooms) = await openSearch(tester);
    rooms.last.responses['queue.add'] = {'entry': entryJson('track-1')};
    await tester.enterText(inSearch(find.byType(EditableText)), '夜曲');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle();

    final row = tester.getRect(
      inSearch(find.widgetWithText(TrackRow, 'track-1')),
    );
    final at = row.centerLeft + const Offset(160, 0);
    await tester.tapAt(
      at,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await settle();
    final pick = find.text('点歌');
    expect(pick, findsWidgets);
    final item = tester.getRect(pick.last);
    expect((item.topLeft - at).distance, lessThan(120));

    await tester.tap(pick.last);
    await settle();
    expect(
      rooms.last.requests.where((request) => request['type'] == 'queue.add'),
      hasLength(1),
    );
  }, variant: desktop);

  testWidgets('a notice shows low in the window, clear of the results and the '
      'mini player', (tester) async {
    final (:settle, router: _, :rooms) = await openSearch(tester);
    rooms.last.responses['queue.add'] = {'entry': entryJson('track-1')};
    await tester.enterText(inSearch(find.byType(EditableText)), '夜曲');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle();

    await tester.tap(find.bySemanticsLabel('点歌《track-1》'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final notice = tester.getRect(find.text('已点歌《track-1》'));
    final window = tester.getRect(find.byType(MaterialApp));
    expect(notice.top, greaterThan(window.height * 0.6));
    expect(
      notice.bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(MiniPlayer).last).top),
    );
  }, variant: desktop);
}
