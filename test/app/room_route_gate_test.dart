import 'dart:async';

import 'package:alisten/app/room_route_gate.dart';
import 'package:alisten/app/router.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/lobby/presentation/join_room_sheet.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../domain/room/room_fixtures.dart';
import '../features/lobby/lobby_test_doubles.dart';
import '../features/playback/playback_test_doubles.dart' show FakeAudioEngine;
import '../features/room/room_test_doubles.dart';
import 'app_test_harness.dart';

const _roomId = '123e4567-e89b-42d3-a456-426614174000';
const _otherId = '223e4567-e89b-42d3-a456-426614174000';

Future<
  ({
    FakeAlistenApi api,
    FakeRoomTransportFactory rooms,
    ProviderContainer container,
    Future<void> Function(String location) go,
  })
>
_openedRoom(WidgetTester tester) async {
  final api = FakeAlistenApi()
    ..rooms = [
      roomListing(id: _roomId, slug: 'listen'),
      roomListing(id: _otherId, slug: 'beta', name: '另一个房间'),
    ];
  final rooms = FakeRoomTransportFactory();
  await pumpAlistenApp(
    tester,
    api: api,
    credentials: FakeCredentialStore()
      ..tickets[_roomId] = 'saved-ticket'
      ..tickets[_otherId] = 'other-ticket',
    rooms: rooms,
  );
  final container = appContainer(tester);
  final router = container.read(routerProvider);
  Future<void> go(String location) async {
    router.go(location);
    await tester.pump();
    await tester.pump();
    // 等页面转场结束。
    await tester.pump(const Duration(seconds: 1));
  }

  await go('/r/listen');
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
  await tester.pump();
  await go('/');
  return (api: api, rooms: rooms, container: container, go: go);
}

void main() {
  testWidgets('the room entered by alias and by id is one room: its '
      'connection, playback and chat stay', (tester) async {
    final api = FakeAlistenApi()
      ..rooms = [roomListing(id: _roomId, slug: 'listen')];
    final rooms = FakeRoomTransportFactory();
    final engine = FakeAudioEngine();
    await pumpAlistenApp(
      tester,
      api: api,
      credentials: FakeCredentialStore()..tickets[_roomId] = 'saved-ticket',
      rooms: rooms,
      engine: engine,
    );
    final container = appContainer(tester);
    final router = container.read(routerProvider);
    Future<void> go(String location) async {
      router.go(location);
      await tester.pump();
      await tester.pump();
      // 等页面转场结束。
      await tester.pump(const Duration(seconds: 1));
    }

    await go('/r/listen');
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
    rooms.last.emit(
      const RoomEventReceived(
        ChatMessageEvent(
          term: 1,
          seq: 2,
          member: testMember,
          content: '晚上好',
          sentAtMs: 1,
        ),
      ),
    );
    await tester.pump();
    final notices = container.read(roomControllerProvider).notices;
    expect(notices, hasLength(1));
    final gate = tester.element(find.byType(RoomRouteGate));

    await go('/r/listen/chat');
    expect(tester.element(find.byType(RoomRouteGate)), same(gate));
    expect(find.text('晚上好'), findsOneWidget);

    await go('/');
    await go('/r/$_roomId/chat');
    expect(find.text('晚上好'), findsOneWidget);
    await go('/r/listen');
    await go('/r/$_roomId');

    expect(rooms.transports, hasLength(1));
    expect(rooms.last.stopCalls, 0);
    expect(api.getRoomCalls, 1);
    expect(engine.releaseCalls, 0);
    final room = container.read(roomControllerProvider);
    expect(room.status, RoomConnectionStatus.open);
    expect(room.notices, same(notices));
  });

  testWidgets('backing out of a room still being looked up does not switch '
      'rooms: the playing room keeps running', (tester) async {
    final (:api, :rooms, :container, :go) = await _openedRoom(tester);
    final snapshot = container.read(roomControllerProvider).snapshot;
    final playing = rooms.last;
    expect(snapshot, isNotNull);

    final lookup = api.getRoomGate = Completer<void>();
    await go('/r/beta');
    expect(find.text('正在进入房间'), findsOneWidget);

    await go('/');
    expect(find.byType(RoomRouteGate), findsNothing);
    lookup.complete();
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();

    expect(api.getRoomCalls, 2);
    expect(rooms.transports, hasLength(1));
    expect(playing.stopCalls, 0);
    final room = container.read(roomControllerProvider);
    expect(room.activeRoomId, _roomId);
    expect(room.snapshot, same(snapshot));
    expect(room.status, RoomConnectionStatus.open);
    expect(api.createTicketCalls, 0);
  });

  testWidgets('a room route shown again after backing out enters the room '
      'once', (tester) async {
    final (:api, :rooms, :container, :go) = await _openedRoom(tester);
    final lookup = api.getRoomGate = Completer<void>();
    await go('/r/beta');
    await go('/');
    await go('/r/beta');
    lookup.complete();
    // 释放正在播放的房间要等流取消，只有真实事件循环能完成。
    await tester.runAsync(pumpEventQueue);
    await tester.pump();

    expect(rooms.transports, hasLength(2));
    expect(rooms.roomIds.last, _otherId);
    expect(container.read(roomControllerProvider).activeRoomId, _otherId);
    expect(rooms.transports.first.stopCalls, 1);
  });

  testWidgets('"返回大厅" of a room that stopped leaves it, and the page '
      'slides out showing what it showed', (tester) async {
    final (:api, :rooms, :container, :go) = await _openedRoom(tester);
    await go('/r/listen');
    rooms.last.disconnect(code: 4404);
    await tester.pump();
    expect(find.text('找不到这个房间'), findsOneWidget);

    await tester.tap(find.text('返回大厅'));
    // 转场途中：房间已经清空，页面还在滑出。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(roomControllerProvider).activeRoomId, isNull);
    expect(find.text('已经切换到其他房间。'), findsNothing);
    expect(find.text('找不到这个房间'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(RoomRouteGate), findsNothing);
    expect(container.read(roomControllerProvider).activeRoomId, isNull);
    expect(find.text(emptyLobbyText), findsNothing);
  });

  testWidgets('"返回大厅" of a room that was refused while another plays '
      'leaves only the page', (tester) async {
    final (:api, :rooms, :container, :go) = await _openedRoom(tester);
    final playing = rooms.last;
    api.getRoomError = const ApiException(
      code: 'NOT_FOUND',
      message: '房间不存在',
      status: 404,
    );
    await go('/r/beta');
    expect(find.text('找不到这个房间'), findsOneWidget);

    await tester.tap(find.text('返回大厅'));
    await tester.pumpAndSettle();

    expect(find.byType(RoomRouteGate), findsNothing);
    expect(playing.stopCalls, 0);
    expect(container.read(roomControllerProvider).activeRoomId, _roomId);
  });

  for (final (how, leave) in <(String, void Function(GoRouter))>[
    ('goes elsewhere', (router) => router.go('/')),
    ('pops', (router) => router.pop()),
  ]) {
    testWidgets('a room still being looked up is not entered once the page '
        '$how, though the answer comes while it slides out', (tester) async {
      final (:api, :rooms, :container, :go) = await _openedRoom(tester);
      final router = container.read(routerProvider);
      final snapshot = container.read(roomControllerProvider).snapshot;
      final playing = rooms.last;
      final lookup = api.getRoomGate = Completer<void>();
      await go('/r/beta');
      expect(find.text('正在进入房间'), findsOneWidget);

      leave(router);
      // 推进一帧：页面已开始离开，但尚未消失。
      await tester.pump();
      lookup.complete();
      await tester.runAsync(pumpEventQueue);
      await tester.pump();

      expect(find.byType(RoomRouteGate), findsOneWidget);
      expect(find.text('正在进入房间'), findsOneWidget);
      expect(find.text('进入房间的请求已被新的操作取代，请重试。'), findsNothing);
      final room = container.read(roomControllerProvider);
      expect(room.activeRoomId, _roomId);
      expect(room.snapshot, same(snapshot));
      expect(playing.stopCalls, 0);
      expect(rooms.transports, hasLength(1));

      await tester.pumpAndSettle();
      expect(find.byType(RoomRouteGate), findsNothing);
      expect(rooms.transports, hasLength(1));
    });
  }

  testWidgets("backing out of the join sheet's room does not cancel the "
      "sheet's own join of it", (tester) async {
    final (:api, :rooms, :container, :go) = await _openedRoom(tester);
    final lookup = api.getRoomGate = Completer<void>();
    await go('/r/beta');

    // 被拒页面上的密码面板同样经房间连接的所有者进入房间。
    final sheet = container
        .read(roomControllerProvider.notifier)
        .openRoom('beta', password: 'secret');
    await go('/');
    lookup.complete();
    await tester.runAsync(pumpEventQueue);
    await tester.pump();

    expect(await tester.runAsync(() => sheet), isA<RoomJoined>());
    expect(container.read(roomControllerProvider).activeRoomId, _otherId);
    expect(rooms.transports, hasLength(2));
    expect(api.createTicketCalls, 0, reason: 'the saved ticket is used');
  });

  testWidgets('backing out of a subpage leaves the request to the room page '
      'below it, which still shows it', (tester) async {
    final (:api, :rooms, :container, :go) = await _openedRoom(tester);
    final router = container.read(routerProvider);
    final lookup = api.getRoomGate = Completer<void>();
    await go('/r/beta/search');

    router.pop();
    await tester.pump();
    lookup.complete();
    await tester.runAsync(pumpEventQueue);
    await tester.pump();

    expect(container.read(roomControllerProvider).activeRoomId, _otherId);
    expect(rooms.transports, hasLength(2));
    expect(find.text('进入房间的请求已被新的操作取代，请重试。'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RoomRouteGate), findsOneWidget);
    expect(find.text('正在连接房间'), findsOneWidget);
  });

  testWidgets('an invite to a room that needs a password asks for it in the '
      "lobby's sheet, which names the room and never its link", (tester) async {
    final api = FakeAlistenApi()
      ..rooms = [
        roomListing(
          id: _roomId,
          slug: 'listen',
          name: '私人房间',
          description: '只放爵士',
          hasPassword: true,
        ),
      ]
      ..ticketError = const ApiException(
        code: 'UNAUTHORIZED',
        message: '需要房间密码',
        status: 401,
      );
    final rooms = FakeRoomTransportFactory();
    await pumpAlistenApp(tester, api: api, rooms: rooms);
    final router = appContainer(tester).read(routerProvider);
    Future<void> settle() async {
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    router.go('/r/listen');
    await settle();
    expect(find.text('需要验证才能进入'), findsOneWidget);

    await tester.tap(find.text('输入密码'));
    await settle();
    final sheet = find.byType(JoinRoomSheet);
    expect(sheet, findsOneWidget);
    Finder inSheet(Finder finder) =>
        find.descendant(of: sheet, matching: finder);
    expect(inSheet(find.text('私人房间')), findsOneWidget);
    expect(inSheet(find.text('只放爵士')), findsOneWidget);
    expect(inSheet(find.text('需要密码')), findsOneWidget);
    expect(inSheet(find.byType(EditableText)), findsOneWidget);
    for (final hidden in ['listen', _roomId.substring(0, 8), 'UUID', '别名']) {
      expect(
        inSheet(find.textContaining(hidden)),
        findsNothing,
        reason: hidden,
      );
    }

    api.ticketError = null;
    await tester.enterText(inSheet(find.byType(EditableText)), 'secret');
    await tester.pump();
    await tester.tap(inSheet(find.text('进入房间')));
    await settle();
    expect(sheet, findsNothing);
    expect(rooms.transports, hasLength(1));
    expect(router.state.uri.path, '/r/listen');
    expect(find.text('正在连接房间'), findsOneWidget);
  });

  testWidgets('"输入密码" pressed again while the sheet is being opened opens '
      'one sheet', (tester) async {
    final api = FakeAlistenApi()
      ..rooms = [roomListing(id: _roomId, slug: 'listen', hasPassword: true)]
      ..ticketError = const ApiException(
        code: 'UNAUTHORIZED',
        message: '需要房间密码',
        status: 401,
      );
    final credentials = FakeCredentialStore();
    await pumpAlistenApp(tester, api: api, credentials: credentials);
    final router = appContainer(tester).read(routerProvider);
    router.go('/r/listen');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final storage = credentials.readTicketGate = Completer<void>();
    await tester.tap(find.text('输入密码'));
    await tester.pump();
    await tester.tap(find.text('输入密码'));
    await tester.pump();
    storage.complete();
    await tester.pumpAndSettle();

    expect(find.byType(JoinRoomSheet), findsOneWidget);
  });

  testWidgets('a room without a password whose ticket ran out is entered '
      'again with a new ticket, without the join sheet', (tester) async {
    final (:api, :rooms, :container, :go) = await _openedRoom(tester);
    await go('/r/listen');
    final transports = rooms.transports.length;
    rooms.last.disconnect(code: 4401);
    await tester.pump();
    expect(find.text('需要验证才能进入'), findsOneWidget);
    expect(find.text('输入密码'), findsNothing);
    final tickets = api.createTicketCalls;

    await tester.tap(find.text('重新进入'));
    await tester.pump();
    // 释放旧连接要等流取消，只有真实事件循环能完成。
    await tester.runAsync(pumpEventQueue);
    await tester.pump();

    expect(find.byType(JoinRoomSheet), findsNothing);
    expect(api.createTicketCalls, tickets + 1);
    expect(rooms.transports, hasLength(transports + 1));
    expect(container.read(roomControllerProvider).failure, isNull);
    expect(find.text('正在连接房间'), findsOneWidget);
  });

  testWidgets('an invite whose room could not be looked up asks for the '
      'password without naming the room by its link', (tester) async {
    final api = FakeAlistenApi()
      ..rooms = [roomListing(id: _roomId, slug: 'listen', hasPassword: true)]
      ..getRoomError = const ApiException(
        code: 'UNAUTHORIZED',
        message: '需要验证',
        status: 401,
      );
    final rooms = FakeRoomTransportFactory();
    await pumpAlistenApp(tester, api: api, rooms: rooms);
    final router = appContainer(tester).read(routerProvider);
    Future<void> settle() async {
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    router.go('/r/listen');
    await settle();
    await tester.tap(find.text('输入密码'));
    await settle();

    final sheet = find.byType(JoinRoomSheet);
    Finder inSheet(Finder finder) =>
        find.descendant(of: sheet, matching: finder);
    expect(inSheet(find.text('这个房间需要密码')), findsOneWidget);
    expect(inSheet(find.byType(EditableText)), findsOneWidget);
    expect(inSheet(find.textContaining('listen')), findsNothing);

    api.getRoomError = null;
    await tester.enterText(inSheet(find.byType(EditableText)), 'secret');
    await tester.pump();
    await tester.tap(inSheet(find.text('进入房间')));
    await settle();
    expect(sheet, findsNothing);
    expect(rooms.roomIds, [_roomId]);
  });

  testWidgets('a room whose first connection fails says so, counts down to '
      'the next attempt and starts it at once when asked', (tester) async {
    final semantics = tester.ensureSemantics();
    final rooms = FakeRoomTransportFactory();
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing(id: _roomId, slug: 'listen')],
      credentials: FakeCredentialStore()..tickets[_roomId] = 'saved-ticket',
      rooms: rooms,
      // 倒计时随测试的时间走。
      overrides: [
        roomNowProvider.overrideWithValue(() => tester.binding.clock.now()),
      ],
    );
    appContainer(tester).read(routerProvider).go('/r/listen');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('正在连接房间'), findsOneWidget);

    final transport = rooms.last..disconnect();
    await tester.pump();
    await tester.pump();
    expect(find.text('暂时连不上房间'), findsOneWidget);
    expect(find.textContaining('3 秒后重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('2 秒后重试'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('连接中断，稍后自动重连')),
      isSemantics(isButton: true, hasTapAction: true),
    );

    await tester.tap(find.textContaining('秒后重试'));
    await tester.pump();
    await tester.pump();
    expect(transport.connectAttempts, 2);
    expect(find.text('暂时连不上房间'), findsOneWidget);
    expect(find.text('正在重连'), findsOneWidget);

    transport.disconnect();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('3 秒后重试'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('连接中断，稍后自动重连')),
      isSemantics(isButton: false, hasTapAction: false),
      reason: 'one immediate retry per disconnect',
    );
    unawaited(transport.stop());
    semantics.dispose();
  });

  testWidgets('after the first failure the page keeps waiting for the '
      'reconnect through every attempt, and says the state only once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final rooms = FakeRoomTransportFactory();
    await pumpAlistenApp(
      tester,
      api: FakeAlistenApi()..rooms = [roomListing(id: _roomId, slug: 'listen')],
      credentials: FakeCredentialStore()..tickets[_roomId] = 'saved-ticket',
      rooms: rooms,
      overrides: [
        roomNowProvider.overrideWithValue(() => tester.binding.clock.now()),
      ],
    );
    appContainer(tester).read(routerProvider).go('/r/listen');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final transport = rooms.last..disconnect();
    await tester.pump();
    await tester.pump();

    final spoken = find.semantics.byLabel(RegExp('连接中断'));
    final spinner = find.descendant(
      of: find.byType(StatusPill),
      matching: find.byType(BusyIndicator),
    );
    expect(find.text('暂时连不上房间'), findsOneWidget);
    expect(spinner, findsNothing);
    expect(spoken.evaluate(), hasLength(1), reason: 'counting down');

    await tester.pump(transport.retryIn);
    await tester.pump();
    expect(transport.connectAttempts, 2);
    expect(find.text('暂时连不上房间'), findsOneWidget);
    expect(find.text('正在连接房间'), findsNothing);
    expect(find.text('正在重连'), findsOneWidget);
    expect(spinner, findsOneWidget);
    expect(spoken.evaluate(), hasLength(1), reason: 'attempt under way');

    transport.disconnect();
    await tester.pump();
    await tester.pump();
    expect(find.text('暂时连不上房间'), findsOneWidget);
    expect(find.textContaining('秒后重试'), findsOneWidget);
    expect(spinner, findsNothing);
    unawaited(transport.stop());
    semantics.dispose();
  });

  testWidgets('entering a refused room again keeps the refusal on the page '
      'and only makes its button busy, while another room plays', (
    tester,
  ) async {
    final (:api, :rooms, :container, :go) = await _openedRoom(tester);
    api.getRoomError = const ApiException(
      code: 'UNAVAILABLE',
      message: '服务暂时不可用',
      status: 503,
    );
    await go('/r/beta');
    expect(find.text('暂时进不了房间'), findsOneWidget);

    final lookup = api.getRoomGate = Completer<void>();
    api.getRoomError = null;
    await tester.tap(find.text('重新进入'));
    await tester.pump();
    await tester.pump();

    expect(api.getRoomCalls, 3);
    expect(find.text('暂时进不了房间'), findsOneWidget);
    expect(find.text('正在进入房间'), findsNothing);
    expect(
      tester.widget<PillButton>(find.widgetWithText(PillButton, '重新进入')).busy,
      isTrue,
    );

    lookup.complete();
    // 释放正在播放的房间要等流取消，只有真实事件循环能完成。
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    expect(container.read(roomControllerProvider).activeRoomId, _otherId);
    expect(find.text('正在连接房间'), findsOneWidget);
    expect(rooms.transports, hasLength(2));
  });

  testWidgets('"返回大厅" while entering again keeps showing the refusal as '
      'the page slides out', (tester) async {
    final (:api, :rooms, :container, :go) = await _openedRoom(tester);
    await go('/r/listen');
    rooms.last.disconnect(code: 1008);
    await tester.pump();
    expect(find.text('暂时进不了房间'), findsOneWidget);

    final lookup = api.getRoomGate = Completer<void>();
    await tester.tap(find.text('重新进入'));
    await tester.pump();
    expect(api.getRoomCalls, 2);

    await tester.tap(find.text('返回大厅'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(roomControllerProvider).activeRoomId, isNull);
    expect(find.text('暂时进不了房间'), findsOneWidget);
    expect(find.text('正在进入房间'), findsNothing);

    lookup.complete();
    await tester.runAsync(pumpEventQueue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('暂时进不了房间'), findsOneWidget);
    expect(find.text('进入房间的请求已被新的操作取代，请重试。'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(RoomRouteGate), findsNothing);
    expect(container.read(roomControllerProvider).activeRoomId, isNull);
  });
}
