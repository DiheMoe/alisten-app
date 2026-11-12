import 'dart:async';
import 'dart:ui' as ui;

import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/queue/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:alisten/shared/ui/edge_fade.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/segmented_pills.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../../../shared/ui/edge_fade_probe.dart';

const _ada = Member(id: 'ada', name: '阿柚', avatarHash: '');

QueueEntry _entry(
  String id, {
  Member? by = _ada,
  bool auto = false,
  int likes = 0,
  QueueEntryStatus status = QueueEntryStatus.ready,
}) {
  return QueueEntry(
    id: id,
    track: testTrack,
    meta: TrackMeta(
      title: '歌$id',
      artist: '歌手',
      album: '专辑',
      coverUrl: 'https://example.com/$id.jpg',
      pageUrl: 'https://example.com/$id',
      durationMs: 180000,
    ),
    requestedBy: by,
    auto: auto,
    likes: likes,
    status: status,
  );
}

RoomSnapshot _snapshot({
  QueueEntry? playing,
  QueueEntry? pending,
  List<QueueEntry> items = const [],
}) {
  return testRoomSnapshot().copyWith(
    term: 1,
    seq: 1,
    nowPlaying: playing == null
        ? null
        : NowPlaying(
            entry: playing,
            mediaUrl: '/media/netease/${playing.id}',
            startedAtMs: 0,
            durationMs: 180000,
            gain: 1,
            lyric: '',
          ),
    pending: pending,
    items: items,
  );
}

typedef _Result = ({MutationResult<Object?> result, String success});

final class _Room {
  _Room(this.tester, this.snapshot, {this.refusal, this.hold});

  final WidgetTester tester;
  RoomSnapshot snapshot;

  void show(RoomSnapshot next) {
    snapshot = next;
    container.invalidate(roomControllerProvider);
  }

  /// 为 null 时房间不答复，结果未知。
  final ({String code, String message})? refusal;

  final Completer<void>? hold;

  int sent = 0;
  final reported = <_Result>[];
  final copied = <String>[];

  late final ProviderContainer container = ProviderContainer(
    overrides: [
      roomControllerProvider.overrideWithBuild(
        (ref, _) => RoomState(
          status: RoomConnectionStatus.open,
          activeRoomId: 'room-id',
          snapshot: snapshot,
          member: _ada,
        ),
      ),
      queueActionsProvider.overrideWithValue(
        QueueActions(<T>(run) async {
          sent++;
          await hold?.future;
          final refusal = this.refusal;
          return refusal == null
              ? MutationUnknown<T>()
              : MutationFailed<T>(refusal.code, refusal.message);
        }),
      ),
    ],
  );

  Widget _app(Widget body) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        home: Scaffold(body: body),
      ),
    );
  }

  Future<void> mount() async {
    await tester.pumpWidget(
      _app(
        QueueView(
          onCopyTitle: copied.add,
          onResult: (result, success) =>
              reported.add((result: result, success: success)),
        ),
      ),
    );
    await tester.pump();
  }

  // 模拟房间页切换到其他模式，队列被别的内容替换。
  Future<void> unmount() async {
    await tester.pumpWidget(_app(const SizedBox.shrink()));
    await tester.pump();
  }

  Future<void> answer() async {
    hold!.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<_Room> _pumpQueue(
  WidgetTester tester,
  RoomSnapshot snapshot, {
  ({String code, String message})? refusal,
  Completer<void>? hold,
}) async {
  tester
    ..view.devicePixelRatio = 1
    ..view.physicalSize = const Size(360, 640);
  addTearDown(tester.view.reset);
  final room = _Room(tester, snapshot, refusal: refusal, hold: hold);
  addTearDown(room.container.dispose);
  await room.mount();
  return room;
}

SemanticsNode _node(WidgetTester tester, String label) {
  return tester.getSemantics(find.bySemanticsLabel(RegExp(label)));
}

bool _tappable(WidgetTester tester, String label) {
  return _node(
    tester,
    label,
  ).getSemanticsData().hasAction(ui.SemanticsAction.tap);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// 打开《歌[id]》的“⋯”菜单，返回其中“移除”是否可点；没有这一项时为 null。
Future<bool?> _removable(WidgetTester tester, String id) async {
  await tester.tap(find.bySemanticsLabel('《歌$id》的更多操作'));
  await _settle(tester);
  final remove = find.bySemanticsLabel('移除');
  final result = remove.evaluate().isEmpty ? null : _tappable(tester, '^移除\$');
  await tester.tapAt(const Offset(4, 4));
  await _settle(tester);
  return result;
}

void main() {
  testWidgets('every entry shows its cover, and an automatic one says so', (
    tester,
  ) async {
    await _pumpQueue(
      tester,
      _snapshot(
        playing: _entry('a'),
        pending: _entry('b', status: QueueEntryStatus.preparing),
        items: [_entry('c'), _entry('d', by: null, auto: true), _entry('e')],
      ),
    );

    expect(find.byType(CoverArt), findsNWidgets(5));
    expect(find.text('自动推荐 · 歌手'), findsOneWidget);
  });

  testWidgets('the queue fades row by row into its top and bottom edges', (
    tester,
  ) async {
    await _pumpQueue(
      tester,
      _snapshot(
        playing: _entry('a'),
        pending: _entry('b'),
        items: [for (var index = 0; index < 12; index++) _entry('w$index')],
      ),
    );
    expectFadedByRow(tester, find.byType(QueueView), top: true, bottom: true);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
    await tester.pump();
    expectFadedByRow(tester, find.byType(QueueView), top: true, bottom: true);
  });

  testWidgets('at rest the play mode row sits wholly below the top fade, '
      'so it does not look cut off by the progress above', (tester) async {
    await _pumpQueue(
      tester,
      _snapshot(
        playing: _entry('a'),
        items: [for (var index = 0; index < 12; index++) _entry('w$index')],
      ),
    );
    final fade = find.descendant(
      of: find.byType(QueueView),
      matching: find.byType(EdgeFade),
    );
    final band = tester.getRect(fade).top + tester.widget<EdgeFade>(fade).top;

    final choices = find.byType(SegmentedPills<RoomPlayMode>);
    expect(tester.getRect(choices).top, greaterThanOrEqualTo(band));
    expect(tester.getRect(find.text('播放模式')).top, greaterThanOrEqualTo(band));
  });

  testWidgets('likes the song playing gets slide in like those in the queue', (
    tester,
  ) async {
    final room = await _pumpQueue(tester, _snapshot(playing: _entry('a')));
    expect(find.text('1'), findsNothing);

    room.show(_snapshot(playing: _entry('a', likes: 1)));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    room.show(_snapshot(playing: _entry('a', likes: 2)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('long pressing a song copies its title, wherever it stands', (
    tester,
  ) async {
    final room = await _pumpQueue(
      tester,
      _snapshot(
        playing: _entry('a'),
        pending: _entry('b'),
        items: [_entry('c')],
      ),
    );

    for (final id in ['a', 'b', 'c']) {
      await tester.longPress(
        find.widgetWithText(TrackRow, _entry(id).meta.title),
      );
      await tester.pump();
    }

    expect(room.copied, [
      for (final id in ['a', 'b', 'c']) _entry(id).meta.title,
    ]);
  });

  testWidgets('a room without songs invites to add one', (tester) async {
    await _pumpQueue(tester, _snapshot());

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('还没有歌，点一首吧'), findsOneWidget);
    expect(find.text('等待中 0 首'), findsNothing);
    // 点歌只在底栏有入口，队列里不再放第二个按钮。
    expect(find.text('点歌'), findsNothing);
  });

  testWidgets('with a song playing, nothing waiting is said under its own '
      'header', (tester) async {
    await _pumpQueue(tester, _snapshot(playing: _entry('a')));

    expect(find.text('正在播放'), findsOneWidget);
    expect(find.text('等待中 0 首'), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
    expect(find.text('还没有歌，点一首吧'), findsOneWidget);
    // 点歌只在底栏有入口，队列里不再放第二个按钮。
    expect(find.text('点歌'), findsNothing);
  });

  testWidgets('the queue has no vote to skip', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpQueue(
      tester,
      _snapshot(playing: _entry('a'), items: [_entry('c')]),
    );

    expect(find.text('投票切歌'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('投票切歌')), findsNothing);
    semantics.dispose();
  });

  testWidgets('only a waiting entry can be liked or removed', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpQueue(
      tester,
      _snapshot(
        playing: _entry('a', likes: 1),
        pending: _entry('b', likes: 2),
        items: [_entry('c', likes: 3)],
      ),
    );

    expect(find.bySemanticsLabel(RegExp('^点赞')), findsOneWidget);
    expect(await _removable(tester, 'a'), isNull);
    expect(await _removable(tester, 'b'), isNull);
    expect(await _removable(tester, 'c'), isTrue);
    semantics.dispose();
  });

  testWidgets('removing from the menu asks first, and is sent only once '
      'confirmed', (tester) async {
    final semantics = tester.ensureSemantics();
    final room = await _pumpQueue(
      tester,
      _snapshot(playing: _entry('a'), items: [_entry('c')]),
    );

    Future<void> chooseRemove() async {
      await tester.tap(find.bySemanticsLabel('《歌c》的更多操作'));
      await _settle(tester);
      await tester.tap(find.text('移除'));
      await _settle(tester);
    }

    await chooseRemove();
    expect(find.text('移除这首歌？'), findsOneWidget);
    expect(find.text('《歌c》会从等待的歌里移除。'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await _settle(tester);
    expect(room.sent, 0);

    await chooseRemove();
    await tester.tap(find.widgetWithText(PillButton, '移除'));
    await _settle(tester);
    expect(room.sent, 1);
    expect(room.reported.single.success, '已移除');
    semantics.dispose();
  });

  testWidgets('copying a title is also in every menu', (tester) async {
    final semantics = tester.ensureSemantics();
    final room = await _pumpQueue(
      tester,
      _snapshot(
        playing: _entry('a'),
        pending: _entry('b'),
        items: [_entry('c')],
      ),
    );

    for (final id in ['a', 'b', 'c']) {
      await tester.tap(find.bySemanticsLabel('《歌$id》的更多操作'));
      await _settle(tester);
      await tester.tap(find.text('复制歌名'));
      await _settle(tester);
    }

    expect(room.copied, ['歌a', '歌b', '歌c']);
    semantics.dispose();
  });

  testWidgets('a like that is refused leaves the count and tells the host', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final room = await _pumpQueue(
      tester,
      _snapshot(playing: _entry('a'), items: [_entry('c', likes: 2)]),
      refusal: (code: 'RATE_LIMITED', message: '太快了'),
    );
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^点赞')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('2'), findsOneWidget);
    expect(room.reported, hasLength(1));
    expect(
      room.reported.single.result,
      isA<MutationFailed<Object?>>()
          .having((failed) => failed.code, 'code', 'RATE_LIMITED')
          .having((failed) => failed.message, 'message', '太快了'),
    );
    semantics.dispose();
  });

  testWidgets('a like waiting for the room stays so when the view is rebuilt, '
      'and is sent once', (tester) async {
    final semantics = tester.ensureSemantics();
    final room = await _pumpQueue(
      tester,
      _snapshot(playing: _entry('a'), items: [_entry('c', likes: 2)]),
      hold: Completer<void>(),
    );
    expect(_tappable(tester, '^点赞'), isTrue);
    expect(_node(tester, '^点赞').value, isEmpty);

    await tester.tap(find.bySemanticsLabel(RegExp('^点赞')));
    await tester.pump();
    expect(room.sent, 1);
    expect(_node(tester, '^点赞').value, '进行中');
    expect(_tappable(tester, '^点赞'), isFalse);
    expect(await _removable(tester, 'c'), isFalse);

    await room.unmount();
    await room.mount();

    expect(_node(tester, '^点赞').value, '进行中');
    expect(_tappable(tester, '^点赞'), isFalse);
    expect(await _removable(tester, 'c'), isFalse);
    await tester.tap(find.bySemanticsLabel(RegExp('^点赞')));
    await tester.pump();
    expect(room.sent, 1);

    await room.answer();

    expect(room.sent, 1);
    expect(room.reported, hasLength(1));
    expect(_node(tester, '^点赞').value, isEmpty);
    expect(_tappable(tester, '^点赞'), isTrue);
    expect(await _removable(tester, 'c'), isTrue);
    semantics.dispose();
  });

  testWidgets('the mode already chosen sends nothing; another is sent once '
      'and says it is in progress', (tester) async {
    final semantics = tester.ensureSemantics();
    final room = await _pumpQueue(
      tester,
      _snapshot(playing: _entry('a')),
      hold: Completer<void>(),
    );

    await tester.tap(find.text('顺序'));
    await tester.pump();
    expect(room.sent, 0);
    expect(_node(tester, '^播放模式').value, isEmpty);

    await tester.tap(find.text('随机'));
    await tester.pump();
    expect(room.sent, 1);
    expect(_node(tester, '^播放模式').value, '进行中');
    await tester.tap(find.text('轮流'));
    await tester.pump();
    expect(room.sent, 1);

    await room.answer();

    expect(room.reported.single.success, '已切换为随机播放');
    expect(_node(tester, '^播放模式').value, isEmpty);
    semantics.dispose();
  });

  testWidgets('a like keeps its place as its count grows', (tester) async {
    final semantics = tester.ensureSemantics();
    final widths = <double>[];
    // 测试字体的数字宽高相等，比任何真实字体的数字都宽，预留的宽度在测试字体下
    // 只容得下两位数。
    for (final likes in [0, 9, 10, 99]) {
      await _pumpQueue(
        tester,
        _snapshot(
          playing: _entry('a'),
          items: [_entry('c', likes: likes)],
        ),
      );
      widths.add(tester.getSize(find.bySemanticsLabel(RegExp('^点赞'))).width);
    }

    expect(widths.toSet(), hasLength(1));
    expect(widths.first, greaterThanOrEqualTo(48));
    semantics.dispose();
  });

  testWidgets('a long queue builds only the rows in view', (tester) async {
    await _pumpQueue(
      tester,
      _snapshot(
        playing: _entry('a'),
        items: [for (var index = 0; index < 200; index++) _entry('w$index')],
      ),
    );

    final built = find.byType(TrackRow).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(30));
  });
}
