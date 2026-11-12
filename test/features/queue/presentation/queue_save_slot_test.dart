import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/action_menu.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';

const _ada = Member(id: 'ada', name: '阿柚', avatarHash: '');

QueueEntry _entry(String id, {int likes = 3}) {
  return QueueEntry(
    id: id,
    track: Track(source: TrackSource.netease, id: id),
    meta: TrackMeta(
      title: '一首名字很长很长很长很长的歌$id',
      artist: '歌手',
      album: '专辑',
      coverUrl: '',
      pageUrl: '',
      durationMs: 180000,
    ),
    requestedBy: _ada,
    auto: false,
    likes: likes,
    status: QueueEntryStatus.ready,
  );
}

final _snapshot = testRoomSnapshot().copyWith(
  term: 1,
  seq: 1,
  nowPlaying: NowPlaying(
    entry: _entry('a'),
    mediaUrl: '/media/netease/a',
    startedAtMs: 0,
    durationMs: 180000,
    gain: 1,
    lyric: '',
  ),
  pending: _entry('b'),
  items: [_entry('c')],
);

Future<void> _pump(
  WidgetTester tester, {
  SaveTrackCallback? save,
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(360, 640),
  RoomSnapshot? snapshot,
}) async {
  tester
    ..view.devicePixelRatio = 1
    ..view.physicalSize = size;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      roomControllerProvider.overrideWithBuild(
        (ref, _) => RoomState(
          status: RoomConnectionStatus.open,
          activeRoomId: 'room-id',
          snapshot: snapshot ?? _snapshot,
          member: _ada,
        ),
      ),
      queueActionsProvider.overrideWithValue(
        QueueActions(<T>(run) async => MutationUnknown<T>()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Scaffold(
          body: QueueView(
            onAddSong: () {},
            onResult: (_, _) {},
            onCopyTitle: (_) {},
            onSaveToPlaylist: save,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _menuOf(String id, {bool skipOffstage = true}) => find.byWidgetPredicate(
  (widget) =>
      widget is ActionMenuButton &&
      widget.semanticLabel == '《一首名字很长很长很长很长的歌$id》的更多操作',
  skipOffstage: skipOffstage,
);

Future<void> _openMenu(WidgetTester tester, String id) async {
  await tester.ensureVisible(_menuOf(id, skipOffstage: false));
  await tester.pump();
  await tester.tap(_menuOf(id));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _closeMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('without a way to save, the menus offer copying alone', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    await _openMenu(tester, 'c');
    expect(find.text('复制歌名'), findsOneWidget);
    expect(find.text('保存到歌单'), findsNothing);
    semantics.dispose();
  });

  testWidgets('every row saves its own song from its menu, handing over the '
      'row to open the panel from', (tester) async {
    final semantics = tester.ensureSemantics();
    final asked = <(String, String, bool)>[];
    await _pump(
      tester,
      save: (context, track, title) => asked.add((
        track.id,
        title,
        context.findAncestorWidgetOfExactType<TrackRow>() != null,
      )),
    );

    for (final id in ['a', 'b', 'c']) {
      await _openMenu(tester, id);
      await tester.tap(find.text('保存到歌单'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    expect(asked, [
      for (final id in ['a', 'b', 'c']) (id, '一首名字很长很长很长很长的歌$id', true),
    ]);
    expect(find.text('保存到歌单'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a waiting row shows its like and a menu, nothing else to '
      'squeeze its title', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, save: (_, _, _) {});

    expect(find.byIcon(Icons.playlist_add_rounded), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    final row = find.ancestor(
      of: find.text('一首名字很长很长很长很长的歌c'),
      matching: find.byType(TrackRow),
    );
    final like = find.bySemanticsLabel(RegExp('^点赞《'));
    expect(
      tester.getRect(like).right,
      lessThanOrEqualTo(tester.getRect(_menuOf('c')).left),
    );
    expect(
      tester.getRect(_menuOf('c')).right,
      lessThanOrEqualTo(tester.getRect(row).right),
    );
    semantics.dispose();
  });

  for (final scale in [2.0, 3.0]) {
    testWidgets('the smallest phone at ${scale}x text keeps every row inside '
        'its width, with removing reachable from the menu', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        size: const Size(320, 760),
        textScaler: TextScaler.linear(scale),
        save: (_, _, _) {},
      );
      expect(tester.takeException(), isNull);
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.text('一首名字很长很长很长很长的歌c', skipOffstage: false),
            )
            .didExceedMaxLines,
        isTrue,
      );

      await _openMenu(tester, 'c');
      expect(tester.takeException(), isNull);
      expect(find.text('移除').hitTestable(), findsOneWidget);
      await _closeMenu(tester);
      semantics.dispose();
    });
  }

  for (final scale in [2.0, 3.0]) {
    testWidgets('the smallest phone at ${scale}x text fits a three-digit like '
        'count on the pending and the waiting row', (tester) async {
      await _pump(
        tester,
        size: const Size(320, 760),
        textScaler: TextScaler.linear(scale),
        snapshot: _snapshot.copyWith(
          term: 1,
          seq: 1,
          pending: _entry('b', likes: 128),
          items: [_entry('c', likes: 128)],
        ),
        save: (_, _, _) {},
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(
        find.text('一首名字很长很长很长很长的歌c', skipOffstage: false),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('128'), findsNWidgets(2));
    });
  }
}
