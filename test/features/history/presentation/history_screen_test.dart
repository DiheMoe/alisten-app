import 'dart:async';
import 'dart:convert';

import 'package:alisten/app/router.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/domain/history/listen.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/history/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/index.dart' show PickControl, PickTone;
import 'package:alisten/features/server/data/preferences_server_store.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/app_test_harness.dart';
import '../../../domain/room/room_fixtures.dart';
import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';
import '../../search/search_test_doubles.dart' show entryJson;
import '../../server/server_test_doubles.dart'
    show FakeCredentialStores, serverB;
import '../history_test_doubles.dart';

const _roomId = '123e4567-e89b-42d3-a456-426614174000';

const _day = 24 * 60 * 60 * 1000;

final _now = DateTime(2026, 11, 2, 21).millisecondsSinceEpoch;

const _refused = ApiException(code: 'INTERNAL', message: '服务器出错了', status: 500);

const _clearWarning = '将清空你的全部播放记录，登录同一个账号的其他设备上也会一起清空。';

typedef _Opened = ({
  FakeAlistenApi api,
  ProviderContainer container,
  FakeRoomTransportFactory rooms,
});

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

Future<_Opened> _openHistory(
  WidgetTester tester,
  List<Listen> listens, {
  FakeAlistenApi? api,
  FakeHistoryExporter? exporter,
  FakeCredentialStores? credentialStores,
  Map<String, Object> preferences = const {},
}) async {
  tester.view
    ..physicalSize = const Size(360, 780) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final rooms = FakeRoomTransportFactory();
  final server = (api ?? FakeAlistenApi())
    ..rooms = [roomListing(id: _roomId, slug: 'listen')]
    ..listens = listens;
  await pumpAlistenApp(
    tester,
    api: server,
    credentials: FakeCredentialStore()
      ..memberToken = 'member-token'
      ..tickets[_roomId] = 'saved-ticket',
    credentialStores: credentialStores,
    rooms: rooms,
    exporter: exporter,
    preferences: preferences,
    overrides: [historyNowProvider.overrideWithValue(() => _now)],
  );
  final container = appContainer(tester);
  container.read(routerProvider).go('/history');
  await _settle(tester);
  return (api: server, container: container, rooms: rooms);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void _emitRoom(FakeRoomTransportFactory rooms) {
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
}

void main() {
  for (final (days, perDay) in [(10, 50), (500, 1), (100, 5)]) {
    testWidgets('a full history of $perDay a day over $days days builds only '
        'the rows near the screen', (tester) async {
      await _openHistory(tester, [
        for (var day = 0; day < days; day++)
          for (var index = 0; index < perDay; index++)
            heard('$day-$index', at: _now - day * _day - index * 60000),
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
        heard('day-$day', at: _now - day * _day),
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

  testWidgets('listens are grouped by day under headings that tell how many '
      'played, stay on top and get a floor once rows pass beneath', (
    tester,
  ) async {
    await _openHistory(tester, [
      for (var index = 0; index < 30; index++)
        heard('today-$index', at: _now - index * 60000),
      heard('yesterday', at: _now - _day),
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

  testWidgets('long pressing a row copies its title', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _openHistory(tester, [heard('一首歌', at: _now)]);

    await tester.longPress(find.text('一首歌'));
    await tester.pump();

    expect(copied, '一首歌');
    expect(find.text('已复制歌名'), findsOneWidget);
  });

  testWidgets("a row's menu copies its title and deletes it like a swipe", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final opened = await _openHistory(tester, [heard('一首歌', at: _now)]);

    await tester.tap(find.bySemanticsLabel('《一首歌》的更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制歌名'));
    await tester.pump();
    expect(copied, '一首歌');
    expect(find.text('已复制歌名'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('《一首歌》的更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(opened.api.removedListens.map(trackKey), ['netease:一首歌']);
    expect(find.text('一首歌'), findsNothing);
    semantics.dispose();
  });

  testWidgets('the page says it is loading until the history is read', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final api = FakeAlistenApi();
    final read = Completer<List<Listen>>();
    api.listMyListensResults.add(read);
    await _openHistory(tester, const [], api: api);

    expect(find.bySemanticsLabel('加载中'), findsOneWidget);
    expect(find.text('你的音乐足迹，从这里开始'), findsNothing);

    read.complete([heard('晴天', at: _now)]);
    await _settle(tester);

    expect(find.bySemanticsLabel('加载中'), findsNothing);
    expect(find.text('晴天'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('export and clear wait for a history to act on', (tester) async {
    final semantics = tester.ensureSemantics();
    final api = FakeAlistenApi();
    final read = Completer<List<Listen>>();
    api.listMyListensResults.add(read);
    await _openHistory(tester, const [], api: api);
    void expectDisabled() {
      for (final label in ['导出播放历史', '清空播放历史']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(hasEnabledState: true, isEnabled: false),
          reason: label,
        );
      }
    }

    expectDisabled();
    read.complete(const []);
    await _settle(tester);
    expect(find.text('你的音乐足迹，从这里开始'), findsOneWidget);
    expectDisabled();
    semantics.dispose();
  });

  testWidgets('a history that cannot be read says why and is read again from '
      'the retry button', (tester) async {
    final api = FakeAlistenApi()
      ..listMyListensError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );
    await _openHistory(tester, [heard('晴天', at: _now)], api: api);

    expect(find.text('播放历史没有读出来'), findsOneWidget);
    expect(find.text('网络请求失败，请检查网络后重试。'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('播放历史没有读出来'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );

    api.listMyListensError = null;
    await tester.tap(find.text('重试'));
    await _settle(tester);

    expect(find.text('播放历史没有读出来'), findsNothing);
    expect(find.text('晴天'), findsOneWidget);
  });

  testWidgets('an empty history invites to listen, in the words of the '
      'web', (tester) async {
    await _openHistory(tester, const []);

    expect(find.text('你的音乐足迹，从这里开始'), findsOneWidget);
    expect(find.text('你在房间里听过的歌会记在这里。'), findsOneWidget);
    expect(_filter, findsNothing);
  });

  testWidgets('a filter that matches nothing says so and can be cleared', (
    tester,
  ) async {
    await _openHistory(tester, [heard('晴天', at: _now)]);

    await tester.enterText(_filter, '不存在');
    await _settle(tester);
    expect(find.text('没有找到相关记录'), findsOneWidget);
    expect(find.text('换个关键词，再找找看。'), findsOneWidget);

    await tester.tap(find.text('清除筛选'));
    await _settle(tester);
    expect(find.text('晴天'), findsOneWidget);
  });

  testWidgets('a row swiped away waits for the server, then leaves the list '
      'and says so', (tester) async {
    final opened = await _openHistory(tester, [
      heard('swiped', at: _now),
      heard('kept', at: _now - 60000),
    ]);
    final gate = opened.api.removeMyListenGate = Completer<void>();
    var changes = 0;
    final history = opened.container.listen(
      historyControllerProvider,
      (_, _) => changes++,
    );
    addTearDown(history.close);
    final left = tester.getTopLeft(find.text('swiped')).dx;

    await tester.drag(find.text('swiped'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(
      opened.container.read(historyControllerProvider).listens,
      hasLength(2),
      reason: 'held aside until the server answers',
    );
    expect(tester.getTopLeft(find.text('swiped')).dx, lessThan(left));

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('swiped'), findsNothing);
    expect(find.text('kept'), findsOneWidget);
    expect(find.text('已删除播放记录'), findsOneWidget);
    expect(changes, 1, reason: 'deleted once, and nothing else changed');
    expect(opened.api.removedListens.map(trackKey), ['netease:swiped']);
    expect(
      opened.container
          .read(historyControllerProvider)
          .listens!
          .map((listen) => listen.meta.title),
      ['kept'],
    );
  });

  testWidgets('a row waiting for the server stays slid open when a new song '
      'comes in above it', (tester) async {
    final opened = await _openHistory(tester, [
      heard('swiped', at: _now),
      heard('kept', at: _now - 60000),
    ]);
    final gate = opened.api.removeMyListenGate = Completer<void>();
    final left = tester.getTopLeft(find.text('swiped')).dx;

    await tester.drag(find.text('swiped'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    opened.api.listens = [heard('新歌', at: _now + 1000), ...opened.api.listens];
    await opened.container.read(historyControllerProvider.notifier).load();
    await tester.pumpAndSettle();

    expect(find.text('新歌'), findsOneWidget);
    expect(tester.getTopLeft(find.text('swiped')).dx, lessThan(left));

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('swiped'), findsNothing);
    expect(find.text('已删除播放记录'), findsOneWidget);
  });

  testWidgets('a row the server would not delete slides back and says why', (
    tester,
  ) async {
    final opened = await _openHistory(tester, [heard('swiped', at: _now)]);
    opened.api.removeMyListenError = _refused;
    final left = tester.getTopLeft(find.text('swiped')).dx;

    await tester.drag(find.text('swiped'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('swiped')).dx, left);
    expect(find.text('服务器出错了'), findsOneWidget);
  });

  testWidgets('a delete with an unknown result slides back and says the '
      'history was read again', (tester) async {
    final opened = await _openHistory(tester, [heard('swiped', at: _now)]);
    opened.api.removeMyListenError = const ApiException(
      code: LocalErrorCodes.network,
      message: '网络请求失败，请检查网络后重试。',
      status: null,
    );
    final left = tester.getTopLeft(find.text('swiped')).dx;
    final reads = opened.api.listMyListensCalls;

    await tester.drag(find.text('swiped'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('swiped'), findsOneWidget);
    expect(tester.getTopLeft(find.text('swiped')).dx, left);
    expect(find.text('结果未知，已重新读取播放历史。'), findsOneWidget);
    expect(opened.api.listMyListensCalls, reads + 1);
  });

  testWidgets('the delete action of a screen reader waits for the server the '
      'same way, and a row being deleted can be neither swiped nor deleted '
      'again', (tester) async {
    final semantics = tester.ensureSemantics();
    final opened = await _openHistory(tester, [heard('晴天', at: _now)]);
    final gate = opened.api.removeMyListenGate = Completer<void>();
    final left = tester.getTopLeft(find.text('晴天')).dx;

    // 只有一行，带自定义动作的语义节点就是这一行。
    tester.semantics.customAction(
      find.semantics.byAction(SemanticsAction.customAction),
      const CustomSemanticsAction(label: '删除'),
    );
    await tester.pump();
    expect(find.semantics.byAction(SemanticsAction.customAction), findsNothing);

    await tester.drag(find.text('晴天'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('晴天')).dx, left);
    expect(opened.api.removedListens, hasLength(1));

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('晴天'), findsNothing);
    expect(find.text('已删除播放记录'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('exporting hands every listen to the exporter', (tester) async {
    final semantics = tester.ensureSemantics();
    final exporter = FakeHistoryExporter();
    await _openHistory(tester, [
      heard('晴天', at: _now),
      heard('七里香', at: _now - _day),
    ], exporter: exporter);

    await tester.tap(find.bySemanticsLabel('导出播放历史'));
    await _settle(tester);

    expect(
      exporter.listens.map((listen) => listen.meta.title),
      unorderedEquals(['晴天', '七里香']),
    );
    expect(find.text('导出失败，请稍后重试。'), findsNothing);
    semantics.dispose();
  });

  testWidgets('clearing asks first, warns that other devices lose the '
      'history too, and leaves it empty', (tester) async {
    final semantics = tester.ensureSemantics();
    final opened = await _openHistory(tester, [heard('晴天', at: _now)]);

    await tester.tap(find.bySemanticsLabel('清空播放历史'));
    await tester.pumpAndSettle();
    expect(find.text(_clearWarning), findsOneWidget);
    await tester.tap(find.text('清空').last);
    await tester.pumpAndSettle();

    expect(opened.api.clearMyListensCalls, 1);
    expect(find.text(_clearWarning), findsNothing);
    expect(find.text('你的音乐足迹，从这里开始'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a clear the server refuses keeps the history and says why', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final opened = await _openHistory(tester, [heard('晴天', at: _now)]);
    opened.api.clearMyListensError = _refused;

    await tester.tap(find.bySemanticsLabel('清空播放历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空').last);
    await tester.pumpAndSettle();

    expect(find.text(_clearWarning), findsNothing);
    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('服务器出错了'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the filter shows the words it filters by when the page opens '
      'again', (tester) async {
    final opened = await _openHistory(tester, [
      heard('晴天', at: _now),
      heard('七里香', at: _now - 60000),
    ]);
    opened.container.read(historyControllerProvider.notifier).filter('晴');
    final router = opened.container.read(routerProvider);

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
      heard('晴天', at: _now),
      heard('七里香', at: _now - 60000),
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
    expect(find.text('清空播放历史'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('清空播放历史'), findsNothing);
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
    final opened = await _openHistory(tester, [heard('晴天', at: _now)]);
    final again = find.bySemanticsLabel('再点一次《晴天》');
    // 房间外打开时没有点歌按钮，也没有常驻的提示。
    expect(find.text('进入房间后可点歌'), findsNothing);
    expect(again, findsNothing);

    unawaited(
      opened.container.read(roomControllerProvider.notifier).openRoom('listen'),
    );
    await _settle(tester);
    _emitRoom(opened.rooms);
    await _settle(tester);
    expect(find.text('进入房间后可点歌'), findsNothing);
    expect(
      tester.widget<PickControl>(find.byType(PickControl)).tone,
      PickTone.quiet,
    );
    opened.rooms.last.responses['queue.add'] = {'entry': entryJson('晴天')};

    await tester.tap(again);
    await _settle(tester);
    final adds = [
      for (final request in opened.rooms.last.requests)
        if (request['type'] == 'queue.add') request,
    ];
    expect(adds, hasLength(1));
    expect(find.text('已点歌《晴天》'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a row names the singer, the source only for bilibili, and the '
      'album, leaving out what is empty', (tester) async {
    await _openHistory(tester, [
      heard('网易云的歌', at: _now),
      heard('B 站的歌', at: _now - 60000, source: TrackSource.bilibili),
      heard('无名的歌', at: _now - 120000, artist: ''),
      heard('单曲', at: _now - 180000, album: ''),
    ]);

    expect(find.text('歌手 · 专辑'), findsOneWidget);
    expect(find.text('歌手 · 哔哩哔哩 · 专辑'), findsOneWidget);
    expect(find.text('未知艺术家 · 专辑'), findsOneWidget);
    expect(find.text('歌手'), findsOneWidget);
  });

  testWidgets('a new song in the room comes in on top while the page is '
      'open', (tester) async {
    final opened = await _openHistory(tester, [heard('旧歌', at: _now - 60000)]);
    unawaited(
      opened.container.read(roomControllerProvider.notifier).openRoom('listen'),
    );
    await _settle(tester);
    opened.api.listens = [heard('新歌', at: _now), heard('旧歌', at: _now - 60000)];

    _emitRoom(opened.rooms);
    await _settle(tester);

    expect(find.text('新歌'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('新歌')).dy,
      lessThan(tester.getTopLeft(find.text('旧歌')).dy),
    );
  });

  testWidgets('switching servers with the page open empties the list, then '
      'shows the history on the new server', (tester) async {
    final semantics = tester.ensureSemantics();
    final stores = FakeCredentialStores();
    stores(serverB.id).memberToken = 'token-b';
    final opened = await _openHistory(
      tester,
      [heard('旧服务器的歌', at: _now)],
      credentialStores: stores,
      preferences: {
        PreferencesServerStore.profilesKey: jsonEncode([serverB.toJson()]),
      },
    );
    expect(find.text('旧服务器的歌'), findsOneWidget);
    final read = Completer<List<Listen>>();
    opened.api.listMyListensResults.add(read);

    final switched = opened.container
        .read(serverSwitcherProvider)
        .switchTo(serverB);
    await _settle(tester);
    expect(await switched, isA<SwitchSucceeded>());
    expect(find.text('旧服务器的歌'), findsNothing);
    expect(find.bySemanticsLabel('加载中'), findsOneWidget);

    read.complete([heard('新服务器的歌', at: _now)]);
    await _settle(tester);
    expect(find.text('新服务器的歌'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('switching servers while the page is closed shows the history '
      'on the new server when it opens again', (tester) async {
    final semantics = tester.ensureSemantics();
    final stores = FakeCredentialStores();
    stores(serverB.id).memberToken = 'token-b';
    final opened = await _openHistory(
      tester,
      [heard('旧服务器的歌', at: _now)],
      credentialStores: stores,
      preferences: {
        PreferencesServerStore.profilesKey: jsonEncode([serverB.toJson()]),
      },
    );
    final router = opened.container.read(routerProvider);
    router.go('/');
    await _settle(tester);

    final switched = opened.container
        .read(serverSwitcherProvider)
        .switchTo(serverB);
    await _settle(tester);
    expect(await switched, isA<SwitchSucceeded>());
    expect(opened.container.read(historyControllerProvider).listens, isNull);
    final read = Completer<List<Listen>>();
    opened.api.listMyListensResults.add(read);
    router.go('/history');
    await tester.pump();
    await tester.pump();
    expect(find.text('旧服务器的歌'), findsNothing);
    expect(find.bySemanticsLabel('加载中'), findsOneWidget);
    read.complete([heard('新服务器的歌', at: _now)]);
    await _settle(tester);

    expect(find.text('旧服务器的歌'), findsNothing);
    expect(find.text('新服务器的歌'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('signing in while the page is closed shows the history of the '
      'account when it opens again', (tester) async {
    final semantics = tester.ensureSemantics();
    final opened = await _openHistory(tester, [heard('游客的歌', at: _now)]);
    final router = opened.container.read(routerProvider);
    router.go('/');
    await _settle(tester);

    await opened.container
        .read(identityControllerProvider.notifier)
        .adoptSession(
          (server) => server.login(username: 'mao', password: 'password1'),
        );
    await _settle(tester);
    expect(opened.container.read(historyControllerProvider).listens, isNull);
    final read = Completer<List<Listen>>();
    opened.api.listMyListensResults.add(read);
    router.go('/history');
    await tester.pump();
    await tester.pump();
    expect(find.text('游客的歌'), findsNothing);
    expect(find.bySemanticsLabel('加载中'), findsOneWidget);
    read.complete([heard('账号的歌', at: _now)]);
    await _settle(tester);

    expect(find.text('游客的歌'), findsNothing);
    expect(find.text('账号的歌'), findsOneWidget);
    semantics.dispose();
  });
}
