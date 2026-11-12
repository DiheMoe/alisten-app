import 'dart:async';

import 'package:alisten/app/app.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/search/index.dart' show SharedTextSource;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../domain/room/room_fixtures.dart';
import '../features/lobby/lobby_test_doubles.dart';
import '../features/room/room_test_doubles.dart';
import '../features/search/search_test_doubles.dart';
import '../features/search/share_test_doubles.dart';
import 'app_test_harness.dart';

const _roomId = '123e4567-e89b-42d3-a456-426614174000';
const _heading = '点分享的链接';

final class _App {
  _App._(this.tester, this.rooms, this.shares, this.router);

  final WidgetTester tester;
  final FakeRoomTransportFactory rooms;
  final FakeSharedTextSource shares;
  final GoRouter router;
  Completer<Map<String, Object?>>? _heldAdd;

  FakeRoomTransport get transport => rooms.last;

  // 发往房间队列的歌，表示为（音源，id）。
  List<(Object?, Object?)> get picked => [
    for (final request in transport.requests)
      if (request['type'] == 'queue.add')
        switch (request['data']) {
          {'track': {'source': final source, 'id': final id}} => (source, id),
          _ => (null, null),
        },
  ];

  static Future<_App> start(
    WidgetTester tester, {
    String alias = 'listen',
  }) async {
    tester.view
      ..physicalSize = const Size(360, 780) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final rooms = FakeRoomTransportFactory();
    final shares = FakeSharedTextSource();
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing(id: _roomId, slug: alias)],
      credentials: FakeCredentialStore()..tickets[_roomId] = 'saved-ticket',
      rooms: rooms,
      shares: shares,
    );
    return _App._(
      tester,
      rooms,
      shares,
      appContainer(tester).read(routerProvider),
    );
  }

  // 首次进入时握手报告的房间类型为 [kind]；[open] 为 false 时房间保持连接中，
  // 直到调用 [hello]。
  Future<void> go(
    String route, {
    RoomKind kind = RoomKind.ephemeral,
    bool open = true,
  }) async {
    final entering = rooms.transports.isEmpty;
    router.go(route);
    await settle();
    if (entering && open) await hello(kind: kind);
  }

  // 与房间页的按钮一样，在当前页面之上打开 [route]。
  Future<void> push(String route) async {
    unawaited(router.push<void>(route));
    await settle();
  }

  Future<void> hello({RoomKind kind = RoomKind.ephemeral}) async {
    transport
      ..responses.addAll(defaultSearchAnswers())
      ..emitHello(
        testRoomSnapshot().copyWith(
          term: 1,
          seq: 1,
          room: RoomInfo(id: _roomId, name: '一起听', description: '', kind: kind),
        ),
      );
    await settle();
  }

  Future<void> share(String text) async {
    shares.share(text);
    await settle();
  }

  void holdAdds() {
    transport.requestHandler = (type, data) {
      if (type != 'queue.add') {
        return Future.value(transport.responses[type] ?? const {});
      }
      return (_heldAdd = Completer()).future;
    };
  }

  void answerAdd(String title) {
    _heldAdd!.complete({'entry': entryJson(title)});
  }

  void failAdd(RoomRequestException error) => _heldAdd!.completeError(error);

  Future<void> settle() async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  testWidgets('a song shared while a room is active is offered in a sheet '
      'that names the room, and picked from it', (tester) async {
    final app = await _App.start(tester);
    await app.go('/r/listen');
    app.holdAdds();

    await app.share(neteaseShareText);
    expect(find.text(_heading), findsOneWidget);
    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('网易云'), findsOneWidget);
    expect(find.text('点到「一起听」'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('点歌《晴天》'));
    await tester.pump();
    expect(app.picked, [('netease', '186016')]);

    app.answerAdd('晴天');
    await app.settle();
    expect(find.text(_heading), findsNothing);
    expect(find.text('已点歌《晴天》'), findsOneWidget);

    await app.go('/r/listen/search');
    expect(find.text(_heading), findsNothing, reason: 'the share was picked');
  });

  testWidgets('closing the sheet lets the share go', (tester) async {
    final app = await _App.start(tester);
    await app.go('/r/listen');

    await app.share(neteaseShareText);
    await tester.tap(find.text('取消'));
    await app.settle();
    expect(find.text(_heading), findsNothing);

    await app.go('/r/listen/search');
    expect(find.text(_heading), findsNothing);
    expect(app.picked, isEmpty);
  });

  testWidgets('a website link shared in a temporary room says why it cannot '
      'be picked', (tester) async {
    final app = await _App.start(tester);
    await app.go('/r/listen');

    await app.share('https://example.com/a.mp3');

    expect(find.text(_heading), findsOneWidget);
    expect(find.text('临时房间只能点 B 站链接'), findsOneWidget);
    expect(find.bySemanticsLabel('点这条链接'), findsNothing);
  });

  testWidgets('a song shared while no room is active shows on top of song '
      'search, without a sheet, when that is where the next room opens', (
    tester,
  ) async {
    final app = await _App.start(tester);

    await app.share(neteaseShareText);
    expect(find.text('进入房间后可点这首歌'), findsOneWidget);
    expect(
      find.text(_heading),
      findsNothing,
      reason: 'no sheet without a room',
    );

    await app.go('/r/listen/search');
    app.holdAdds();
    expect(find.text(_heading), findsOneWidget);
    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('取消'), findsNothing, reason: 'no sheet over song search');
    expect(find.textContaining('点到「'), findsNothing);

    await tester.tap(find.bySemanticsLabel('点歌《晴天》'));
    await tester.pump();
    app.answerAdd('晴天');
    await app.settle();
    expect(app.picked, [('netease', '186016')]);
    expect(find.text(_heading), findsNothing);
  });

  testWidgets('a song shared while no room is active is offered in a sheet '
      'once the room entered next opens', (tester) async {
    final app = await _App.start(tester);
    await app.share(neteaseShareText);
    expect(find.text(_heading), findsNothing);

    await app.go('/r/listen');
    app.holdAdds();
    expect(find.text(_heading), findsOneWidget);
    expect(find.text('点到「一起听」'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('点歌《晴天》'));
    await tester.pump();
    app.answerAdd('晴天');
    await app.settle();
    expect(app.picked, [('netease', '186016')]);
    expect(find.text(_heading), findsNothing);

    await app.go('/r/listen/search');
    expect(find.text(_heading), findsNothing, reason: 'offered once');
  });

  // 别名与点歌页、歌单页的路径片段相同时，房间页也不能被误认为它们。
  for (final (alias, route) in [
    ('search', '/r/search'),
    ('playlists', '/r/playlists/queue'),
  ]) {
    testWidgets('a song shared while no room is active is offered in a sheet '
        'once room "$alias" opens at $route', (tester) async {
      final app = await _App.start(tester, alias: alias);
      await app.share(neteaseShareText);
      expect(find.text('进入房间后可点这首歌'), findsOneWidget);

      await app.go(route);

      expect(find.text(_heading), findsOneWidget);
      expect(find.text('点到「一起听」'), findsOneWidget);
    });
  }

  for (final playlist in [false, true]) {
    testWidgets('a song shared while no room is active shows once, on top of '
        'song search, when song search${playlist ? ' and a playlist' : ''} '
        'opened above the room before it did', (tester) async {
      final app = await _App.start(tester);
      await app.share(neteaseShareText);

      await app.go('/r/listen', open: false);
      await app.push('/r/listen/search');
      if (playlist) await app.push('/r/listen/playlists/netease/1');
      await app.hello();
      expect(find.text('取消'), findsNothing, reason: 'no sheet');
      expect(find.textContaining('点到「'), findsNothing);

      if (playlist) {
        app.router.pop();
        await app.settle();
      }
      expect(find.text(_heading), findsOneWidget);
      expect(find.text('晴天'), findsOneWidget);
    });
  }

  for (final (outcome, error, shown) in [
    (
      'is lost',
      const RoomRequestException(
        message: '连接已断开，结果未知。',
        outcome: RoomRequestOutcome.unknown,
      ),
      '结果未知',
    ),
    (
      'is refused',
      const RoomRequestException(
        message: '队列已满',
        outcome: RoomRequestOutcome.failed,
        code: 'QUEUE_FULL',
      ),
      '失败',
    ),
  ]) {
    testWidgets('a pick from the sheet whose answer $outcome keeps the sheet '
        'and is not sent again', (tester) async {
      final app = await _App.start(tester);
      await app.go('/r/listen');
      app.holdAdds();
      await app.share(neteaseShareText);

      await tester.tap(find.bySemanticsLabel('点歌《晴天》'));
      await tester.pump();
      app.failAdd(error);
      await app.settle();
      await tester.pump(const Duration(seconds: 5));

      expect(find.text(_heading), findsOneWidget);
      expect(find.text(shown), findsOneWidget);
      expect(app.picked, hasLength(1));
    });
  }

  testWidgets('without a room, a share that can never be picked is let go '
      'with the reason', (tester) async {
    final app = await _App.start(tester);

    await app.share('https://music.163.com/#/playlist?id=1');
    expect(find.text('只支持单曲链接'), findsOneWidget);

    await app.share('分享一首歌');
    expect(find.text('分享的内容里没有链接'), findsOneWidget);

    await app.go('/r/listen/search');
    expect(find.text(_heading), findsNothing);
  });

  testWidgets('a share that cannot be read once the app runs is told to the '
      'user and logged by its type alone, and later shares still arrive', (
    tester,
  ) async {
    final records = <(String, int, String)>[];
    AppLog.onRecord = (name, level, message) =>
        records.add((name, level, message));
    addTearDown(() => AppLog.onRecord = null);
    final app = await _App.start(tester);

    app.shares.fail(StateError('https://163cn.tv/secret'));
    await app.settle();

    expect(tester.takeException(), isNull);
    expect(find.text('没能读取分享的内容'), findsOneWidget);
    expect(find.textContaining('163cn'), findsNothing);
    expect(records.where((record) => record.$3.contains('163cn')), isEmpty);
    expect(
      records.where(
        (record) =>
            record.$1 == 'alisten.share' &&
            record.$3.contains('type=StateError'),
      ),
      hasLength(1),
    );

    await app.share('分享一首歌');
    expect(find.text('分享的内容里没有链接'), findsOneWidget);
  });

  testWidgets('shares that cannot be followed are told to the user and logged '
      'as an error, both without the link, and the app runs on', (
    tester,
  ) async {
    final records = <(String, int, String)>[];
    AppLog.onRecord = (name, level, message) =>
        records.add((name, level, message));
    addTearDown(() => AppLog.onRecord = null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: await alistenAppOverrides(shares: _UnreadableShares()),
        child: const AlistenApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('创建房间'), findsOneWidget);
    final errors = [
      for (final record in records)
        if (record.$2 >= 1000) record,
    ];
    expect(errors, [('alisten.share', 1000, 'shares not followed')]);
    expect(records.where((record) => record.$3.contains('http')), isEmpty);
    expect(find.text('没能读取分享的内容'), findsOneWidget);
    expect(find.textContaining('163cn'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

/// 读取分享即出错，且错误信息含链接。
final class _UnreadableShares implements SharedTextSource {
  @override
  Stream<String> get texts => throw StateError('https://163cn.tv/secret');
}
