import 'package:alisten/app/room/room_mode.dart';
import 'package:alisten/app/room/room_mode_bar.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final position = ValueNotifier<double>(0);
  tearDown(() => position.value = 0);

  Widget bar(RoomMode mode, {bool reduced = false}) => MediaQuery(
    data: MediaQueryData(
      size: const Size(400, 800),
      disableAnimations: reduced,
    ),
    child: MaterialApp(
      theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: RoomModeBar(
            mode: mode,
            position: position,
            onSelect: (_) {},
            onSearch: () {},
            onPickFromPlaylists: () {},
          ),
        ),
      ),
    ),
  );

  Rect tab(WidgetTester tester, String label) => tester.getRect(
    find.ancestor(of: find.text(label), matching: find.byType(SizedBox)).last,
  );

  // 文字露出了多少：0 是只剩图标。
  double shown(WidgetTester tester, String label) => tester
      .widget<Opacity>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Opacity))
            .first,
      )
      .opacity;

  testWidgets('only the mode on screen shows its name, in a wider tab; the '
      'player shows none', (tester) async {
    await tester.pumpWidget(bar(RoomMode.queue));
    expect(shown(tester, '队列'), 1);
    expect(shown(tester, '歌词'), 0);
    expect(shown(tester, '聊天'), 0);
    expect(tab(tester, '队列').width, greaterThan(tab(tester, '歌词').width));
    expect(tab(tester, '歌词').width, closeTo(tab(tester, '聊天').width, 0.01));

    await tester.pumpWidget(bar(RoomMode.player));
    await tester.pumpAndSettle();
    for (final label in ['歌词', '队列', '聊天']) {
      expect(shown(tester, label), 0);
    }
    expect(tab(tester, '歌词').width, closeTo(tab(tester, '队列').width, 0.01));
  });

  testWidgets('switching, one tab opens and the other closes smoothly '
      'without overshooting', (tester) async {
    await tester.pumpWidget(bar(RoomMode.lyrics));
    final open = tab(tester, '歌词').width;
    final closed = tab(tester, '聊天').width;

    await tester.pumpWidget(bar(RoomMode.chat));
    var chat = tab(tester, '聊天').width;
    var lyrics = tab(tester, '歌词').width;
    for (var frame = 0; frame < 25; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final nextChat = tab(tester, '聊天').width;
      final nextLyrics = tab(tester, '歌词').width;
      expect(nextChat, greaterThanOrEqualTo(chat - 0.01));
      expect(nextLyrics, lessThanOrEqualTo(lyrics + 0.01));
      expect(nextChat, lessThanOrEqualTo(open + 0.01));
      chat = nextChat;
      lyrics = nextLyrics;
    }
    await tester.pumpAndSettle();
    expect(tab(tester, '聊天').width, closeTo(open, 0.5));
    expect(tab(tester, '歌词').width, closeTo(closed, 0.5));
    expect(shown(tester, '聊天'), 1);
    expect(shown(tester, '歌词'), 0);
  });

  testWidgets('the selection follows a swipe between two tabs', (tester) async {
    await tester.pumpWidget(bar(RoomMode.lyrics));
    final lyrics = tab(tester, '歌词');
    final queue = tab(tester, '队列');
    final thumb = find.descendant(
      of: find.byType(RoomModeBar),
      matching: find.byType(CustomPaint),
    );
    final paint = tester.getRect(thumb.last);

    position.value = 0.5;
    await tester.pump();
    final halfway = Rect.lerp(lyrics, queue, 0.5)!.shift(-paint.topLeft);
    expect(
      tester.renderObject(thumb.last),
      paints..rrect(
        rrect: BorderRadius.circular(
          14,
        ).toRRect(Rect.fromLTWH(halfway.left, 0, halfway.width, paint.height)),
      ),
    );
  });

  testWidgets('without animations the tabs change at once', (tester) async {
    await tester.pumpWidget(bar(RoomMode.lyrics, reduced: true));
    await tester.pumpWidget(bar(RoomMode.queue, reduced: true));
    await tester.pump();
    expect(shown(tester, '队列'), 1);
    expect(shown(tester, '歌词'), 0);
  });

  testWidgets('every tab is still read by its name', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(bar(RoomMode.player));
    for (final label in ['歌词', '队列', '聊天']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    semantics.dispose();
  });
}
