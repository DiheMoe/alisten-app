import 'dart:async';
import 'dart:convert';

import 'package:alisten/app/router.dart';
import 'package:alisten/domain/history/play_record.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/history/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/index.dart' show PickControl;
import 'package:alisten/features/server/data/preferences_server_store.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/app_test_harness.dart';
import '../../../domain/room/room_fixtures.dart';
import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';
import '../../search/search_test_doubles.dart' show entryJson;
import '../../server/server_test_doubles.dart' show serverB;
import '../history_test_doubles.dart';

const _roomId = '123e4567-e89b-42d3-a456-426614174000';

const _day = 24 * 60 * 60 * 1000;

final _now = DateTime(2026, 11, 2, 21).millisecondsSinceEpoch;

// 歌名同时用作曲目 ID，使列表行与记录可按歌名对应。
PlayRecord _played(
  String title, {
  required int at,
  String roomName = '一起听',
  String serverOrigin = 'https://livehouse.dihe.moe',
}) {
  return PlayRecord(
    roomId: 'room',
    roomName: roomName,
    serverOrigin: serverOrigin,
    track: Track(source: TrackSource.netease, id: title),
    meta: TrackMeta(
      title: title,
      artist: '歌手',
      album: '专辑',
      coverUrl: '',
      pageUrl: '',
      durationMs: 180000,
    ),
    playedAtMs: at,
  );
}

Finder get _filter => find.descendant(
  of: find.byType(AlistenTextField),
  matching: find.byType(EditableText),
);

Finder get _focused => find.byWidgetPredicate(
  (widget) => widget is EditableText && widget.focusNode.hasFocus,
);

// 筛选框中也有 `Scrollable`，这里只取记录列表。
Finder get _list => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

Future<({FakeRoomTransportFactory rooms, ProviderContainer container})>
_openHistory(
  WidgetTester tester,
  List<PlayRecord> records, {
  List<Object?>? stored,
  FakeHistoryExporter? exporter,
  ServerProfile? currentServer,
}) async {
  tester.view
    ..physicalSize = const Size(360, 780) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final rooms = FakeRoomTransportFactory();
  await pumpAlistenApp(
    tester,
    api: FakeAlistenApi()..rooms = [roomListing(id: _roomId, slug: 'listen')],
    credentials: FakeCredentialStore()..tickets[_roomId] = 'saved-ticket',
    rooms: rooms,
    exporter: exporter,
    preferences: {
      'alisten.play-history': jsonEncode(
        stored ?? [for (final record in records) record.toJson()],
      ),
      if (currentServer != null) ...{
        PreferencesServerStore.profilesKey: jsonEncode([
          currentServer.toJson(),
        ]),
        PreferencesServerStore.currentKey: currentServer.id,
      },
    },
    overrides: [historyNowProvider.overrideWithValue(() => _now)],
  );
  final container = appContainer(tester);
  container.read(routerProvider).go('/history');
  await _settle(tester);
  return (rooms: rooms, container: container);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  for (final (days, perDay) in [(10, 50), (500, 1), (100, 5)]) {
    testWidgets('a full history of $perDay a day over $days days builds only '
        'the rows near the screen', (tester) async {
      await _openHistory(tester, [
        for (var day = 0; day < days; day++)
          for (var index = 0; index < perDay; index++)
            _played('$day-$index', at: _now - day * _day - index * 60000),
      ]);

      final built = find
          .byType(TrackRow, skipOffstage: false)
          .evaluate()
          .length;
      expect(built, greaterThan(0));
      expect(built, lessThan(40));
    });
  }

  testWidgets('older days come in as the list nears its end, and filtering '
      'starts again from the latest', (tester) async {
    await _openHistory(tester, [
      for (var day = 0; day < 30; day++)
        _played('day-$day', at: _now - day * _day),
    ]);
    expect(find.text('day-29', skipOffstage: false), findsNothing);

    await tester.scrollUntilVisible(
      find.text('day-29'),
      400,
      scrollable: _list,
    );
    expect(find.text('day-29'), findsOneWidget);

    await tester.enterText(_filter, 'day');
    await _settle(tester);
    expect(find.text('day-0'), findsOneWidget);
    expect(find.text('day-29', skipOffstage: false), findsNothing);
  });

  testWidgets('records are grouped by day under headings that tell how many '
      'played, stay on top and get a floor once rows pass beneath', (
    tester,
  ) async {
    await _openHistory(tester, [
      for (var index = 0; index < 30; index++)
        _played('today-$index', at: _now - index * 60000),
      _played('yesterday', at: _now - _day),
    ]);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('30 首'), findsOneWidget);
    Color floorOf(String heading) => tester
        .widget<ColoredBox>(
          find
              .ancestor(
                of: find.text(heading),
                matching: find.byType(ColoredBox),
              )
              .first,
        )
        .color;
    expect(floorOf('今天').a, 0);

    final heading = tester.getTopLeft(find.text('今天')).dy;
    await tester.drag(find.text('today-0'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('今天'), findsOneWidget);
    expect(tester.getTopLeft(find.text('今天')).dy, lessThanOrEqualTo(heading));
    expect(find.text('today-0'), findsNothing);
    expect(floorOf('今天').a, greaterThan(0.9));
  });

  testWidgets('a row swiped away is deleted once and leaves the list', (
    tester,
  ) async {
    final (:rooms, :container) = await _openHistory(tester, [
      _played('swiped', at: _now),
      _played('kept', at: _now - 60000),
    ]);
    expect(find.text('swiped'), findsOneWidget);
    var changes = 0;
    final history = container.listen(
      historyControllerProvider,
      (_, _) => changes++,
    );
    addTearDown(history.close);

    await tester.drag(find.text('swiped'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('swiped'), findsNothing);
    expect(find.text('kept'), findsOneWidget);
    expect(changes, 1, reason: 'deleted once, and nothing else changed');
    String titles(List<PlayRecord> records) =>
        records.map((record) => record.meta.title).join();
    expect(titles(container.read(historyControllerProvider).records), 'kept');
    expect(
      titles(container.read(playHistoryStoreProvider).loadPlays()),
      'kept',
    );
  });

  testWidgets('a row swiped away comes back where it was from the toast', (
    tester,
  ) async {
    final (:rooms, :container) = await _openHistory(tester, [
      _played('newest', at: _now),
      _played('middle', at: _now - 60000),
      _played('oldest', at: _now - 120000),
    ]);

    await tester.drag(find.text('middle'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('middle'), findsNothing);
    expect(find.text('已删除《middle》'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    double top(String title) => tester.getTopLeft(find.text(title)).dy;
    expect(top('newest'), lessThan(top('middle')));
    expect(top('middle'), lessThan(top('oldest')));
    expect(
      container
          .read(playHistoryStoreProvider)
          .loadPlays()
          .map((record) => record.meta.title),
      ['newest', 'middle', 'oldest'],
    );
  });

  testWidgets('exporting hands every stored record to the exporter', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final exporter = FakeHistoryExporter();
    await _openHistory(tester, [
      _played('晴天', at: _now),
      _played('七里香', at: _now - _day),
    ], exporter: exporter);

    await tester.tap(find.bySemanticsLabel('导出播放历史'));
    await _settle(tester);

    expect(
      exporter.records.map((record) => record.meta.title),
      unorderedEquals(['晴天', '七里香']),
    );
    expect(find.text('导出失败，请稍后重试。'), findsNothing);
    semantics.dispose();
  });

  testWidgets('clearing the history takes back the offer to undo a delete', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (:rooms, :container) = await _openHistory(tester, [
      _played('swiped', at: _now),
      _played('kept', at: _now - 60000),
    ]);
    await tester.drag(find.text('swiped'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('清空播放历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空').last);
    await tester.pumpAndSettle();

    expect(find.text('已删除《swiped》'), findsNothing);
    expect(find.text('撤销'), findsNothing);
    expect(container.read(historyControllerProvider).records, isEmpty);
    semantics.dispose();
  });

  testWidgets('the filter shows the words it filters by when the page opens '
      'again', (tester) async {
    final (:rooms, :container) = await _openHistory(tester, [
      _played('晴天', at: _now),
      _played('七里香', at: _now - 60000),
    ]);
    container.read(historyControllerProvider.notifier).filter('晴');
    final router = container.read(routerProvider);

    router.go('/');
    await _settle(tester);
    router.go('/history');
    await _settle(tester);

    expect(tester.widget<EditableText>(_filter).controller.text, '晴');
    expect(_focused, findsNothing, reason: 'shown, but no keyboard');
  });

  testWidgets('the filter stays open but leaves the keyboard down after a '
      'tap outside it, a sheet over it, or a trip to the background', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _openHistory(tester, [
      _played('晴天', at: _now),
      _played('七里香', at: _now - 60000),
    ]);
    Future<void> type() async {
      await tester.tap(_filter);
      await _settle(tester);
      expect(_focused, findsOneWidget);
    }

    await type();
    await tester.tapAt(
      tester.getCenter(find.text('七里香')) + const Offset(0, 200),
    );
    await _settle(tester);
    expect(_focused, findsNothing);
    expect(_filter, findsOneWidget);

    // 读屏的点按不经过指针，点按外部不会先放下焦点。
    await type();
    tester.semantics.tap(find.semantics.byLabel('清空播放历史'));
    await tester.pumpAndSettle();
    expect(find.text('清空播放历史？'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('清空播放历史？'), findsNothing);
    expect(_focused, findsNothing);

    await type();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await _settle(tester);
    }
    expect(_focused, findsNothing);
    expect(_filter, findsOneWidget);
    semantics.dispose();
  });

  testWidgets('playing a song again waits for a room, then adds it to the '
      'room and says so', (tester) async {
    final semantics = tester.ensureSemantics();
    final (:rooms, :container) = await _openHistory(tester, [
      _played('晴天', roomName: '老房间', at: _now),
    ]);
    final again = find.bySemanticsLabel('再点一次《晴天》');
    expect(find.text('进入房间后可点歌'), findsOneWidget);
    expect(tester.widget<PickControl>(find.byType(PickControl)).subtle, isTrue);
    expect(
      tester.getSemantics(again),
      isSemantics(hasEnabledState: true, isEnabled: false, hasTapAction: false),
    );
    expect(find.textContaining('老房间'), findsOneWidget);

    unawaited(
      container.read(roomControllerProvider.notifier).openRoom('listen'),
    );
    await _settle(tester);
    rooms.last.emitHello(
      testRoomSnapshot().copyWith(
        term: 1,
        seq: 1,
        room: const RoomInfo(
          id: _roomId,
          name: '一起听',
          description: '',
          kind: RoomKind.ephemeral,
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('进入房间后可点歌'), findsNothing);
    rooms.last.responses['queue.add'] = {'entry': entryJson('晴天')};

    await tester.tap(again);
    await _settle(tester);
    final adds = [
      for (final request in rooms.last.requests)
        if (request['type'] == 'queue.add') request,
    ];
    expect(adds, hasLength(1));
    expect(find.text('已点歌《晴天》'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a record from another server names that server after the '
      'room, one from the current server does not', (tester) async {
    await _openHistory(tester, [
      _played('晴天', roomName: '大厅', at: _now),
      _played(
        '七里香',
        roomName: '大厅',
        serverOrigin: 'https://example.com:8443',
        at: _now - 60000,
      ),
    ]);

    expect(find.text('歌手 · 大厅'), findsOneWidget);
    expect(find.text('歌手 · 大厅 · example.com:8443'), findsOneWidget);
  });

  testWidgets('with another server current, the records of the default '
      'server name theirs', (tester) async {
    await _openHistory(tester, [
      _played('晴天', roomName: '大厅', at: _now),
      _played(
        '七里香',
        roomName: '大厅',
        serverOrigin: 'https://example.com:8443',
        at: _now - 60000,
      ),
    ], currentServer: serverB);

    expect(find.text('歌手 · 大厅 · livehouse.dihe.moe'), findsOneWidget);
    expect(find.text('歌手 · 大厅'), findsOneWidget);
  });

  testWidgets('a record stored before servers were kept belongs to the '
      'default server', (tester) async {
    final old = Map<String, Object?>.of(
      _played('晴天', roomName: '大厅', at: _now).toJson(),
    )..remove('serverOrigin');

    await _openHistory(tester, const [], stored: [old]);

    expect(find.text('歌手 · 大厅'), findsOneWidget);
  });

  testWidgets('with another server current, a record stored before servers '
      'were kept still belongs to the default server', (tester) async {
    final old = Map<String, Object?>.of(
      _played('晴天', roomName: '大厅', at: _now).toJson(),
    )..remove('serverOrigin');

    await _openHistory(tester, const [], stored: [old], currentServer: serverB);

    expect(find.text('歌手 · 大厅 · livehouse.dihe.moe'), findsOneWidget);
  });

  testWidgets('a record without a room name still names its other '
      'server', (tester) async {
    await _openHistory(tester, [
      _played(
        '晴天',
        roomName: '',
        serverOrigin: 'https://example.com:8443',
        at: _now,
      ),
    ]);

    expect(find.text('歌手 · example.com:8443'), findsOneWidget);
  });

  testWidgets('playing a song of another server again adds it to the room '
      'that is open now', (tester) async {
    final semantics = tester.ensureSemantics();
    final (:rooms, :container) = await _openHistory(tester, [
      _played(
        '七里香',
        roomName: '大厅',
        serverOrigin: 'https://example.com:8443',
        at: _now,
      ),
    ]);
    unawaited(
      container.read(roomControllerProvider.notifier).openRoom('listen'),
    );
    await _settle(tester);
    rooms.last.emitHello(
      testRoomSnapshot().copyWith(
        term: 1,
        seq: 1,
        room: const RoomInfo(
          id: _roomId,
          name: '一起听',
          description: '',
          kind: RoomKind.ephemeral,
        ),
      ),
    );
    await _settle(tester);
    rooms.last.responses['queue.add'] = {'entry': entryJson('七里香')};

    await tester.tap(find.bySemanticsLabel('再点一次《七里香》'));
    await _settle(tester);

    final adds = [
      for (final request in rooms.last.requests)
        if (request['type'] == 'queue.add') request,
    ];
    expect(adds, hasLength(1));
    expect(find.text('已点歌《七里香》'), findsOneWidget);
    semantics.dispose();
  });
}
