import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
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
  Widget Function(Track track, String title)? save,
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
            saveToPlaylist: save,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('without a slot the rows have no save button', (tester) async {
    await _pump(tester);

    expect(find.byIcon(Icons.playlist_add_rounded), findsNothing);
  });

  testWidgets('every row puts the slot first at its end, with its own '
      'song', (tester) async {
    final semantics = tester.ensureSemantics();
    final asked = <(String, String)>[];
    await _pump(
      tester,
      save: (track, title) {
        asked.add((track.id, title));
        return IconCircleButton(
          icon: Icons.playlist_add_rounded,
          semanticLabel: '保存${track.id}',
          style: IconCircleButtonStyle.plain,
          iconSize: AlistenSizes.iconSm,
          onPressed: () {},
        );
      },
    );

    expect(asked.toSet(), {
      for (final id in ['a', 'b', 'c']) (id, '一首名字很长很长很长很长的歌$id'),
    });
    Finder inRow(String id, Finder finder) => find.descendant(
      of: find.ancestor(
        of: find.text('一首名字很长很长很长很长的歌$id'),
        matching: find.byType(TrackRow),
      ),
      matching: finder,
    );
    double saveEnd(String id) =>
        tester.getRect(find.bySemanticsLabel('保存$id')).right;
    final likes = find.byIcon(Icons.favorite_border_rounded);
    expect(
      saveEnd('a'),
      lessThanOrEqualTo(tester.getRect(inRow('a', likes)).left),
    );
    expect(
      saveEnd('a'),
      lessThanOrEqualTo(
        tester.getRect(inRow('a', find.byIcon(Icons.graphic_eq_rounded))).left,
      ),
    );
    expect(
      saveEnd('b'),
      lessThanOrEqualTo(tester.getRect(inRow('b', likes)).left),
    );
    expect(
      saveEnd('c'),
      lessThanOrEqualTo(
        tester.getRect(find.bySemanticsLabel(RegExp('^点赞《'))).left,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a narrow phone at twice the text size keeps the buttons and '
      'cuts the title', (tester) async {
    await _pump(
      tester,
      textScaler: const TextScaler.linear(2),
      save: (track, title) => IconCircleButton(
        icon: Icons.playlist_add_rounded,
        semanticLabel: '保存',
        style: IconCircleButtonStyle.plain,
        iconSize: AlistenSizes.iconSm,
        onPressed: () {},
      ),
    );

    expect(tester.takeException(), isNull);
    final saves = find.ancestor(
      of: find.byIcon(Icons.playlist_add_rounded),
      matching: find.byType(IconCircleButton),
    );
    expect(saves, findsNWidgets(3));
    for (final save in saves.evaluate()) {
      expect(save.size, const Size.square(AlistenSizes.minTouchTarget));
    }
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('一首名字很长很长很长很长的歌c'))
          .didExceedMaxLines,
      isTrue,
    );
  });

  for (final scale in [2.0, 3.0]) {
    testWidgets('the smallest phone at ${scale}x text keeps the waiting row '
        'inside its width, with the remove button reachable', (tester) async {
      await _pump(
        tester,
        size: const Size(320, 760),
        textScaler: TextScaler.linear(scale),
        save: (track, title) => IconCircleButton(
          icon: Icons.playlist_add_rounded,
          semanticLabel: '保存',
          style: IconCircleButtonStyle.plain,
          iconSize: AlistenSizes.iconSm,
          onPressed: () {},
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(
        find.byIcon(Icons.close_rounded, skipOffstage: false),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.close_rounded).hitTestable(), findsOneWidget);
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
        save: (track, title) => IconCircleButton(
          icon: Icons.playlist_add_rounded,
          semanticLabel: '保存',
          style: IconCircleButtonStyle.plain,
          iconSize: AlistenSizes.iconSm,
          onPressed: () {},
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(
        find.byIcon(Icons.close_rounded, skipOffstage: false),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('128'), findsNWidgets(2));
    });
  }
}
