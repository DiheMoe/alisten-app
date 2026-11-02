import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/application/last_room_store.dart';
import 'package:alisten/features/room/application/room_controller.dart';
import 'package:alisten/features/room/application/room_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../domain/room/room_fixtures.dart';
import '../../lobby/lobby_test_doubles.dart';
import '../room_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late FakeRoomTransportFactory factory;
  late FakeLastRoomStore lastRoom;
  late ProviderContainer container;
  late RoomController controller;

  setUp(() {
    api = FakeAlistenApi()..rooms = [roomListing()];
    credentials = FakeCredentialStore();
    factory = FakeRoomTransportFactory();
    lastRoom = FakeLastRoomStore();
    container = ProviderContainer(
      overrides: [
        alistenApiProvider.overrideWithValue(api),
        credentialStoreProvider.overrideWithValue(credentials),
        roomTransportFactoryProvider.overrideWithValue(factory.call),
        ...roomDeviceOverrides(lastRoom: lastRoom),
        clearLocalEmailProvider.overrideWithValue(() async {}),
      ],
    );
    controller = container.read(roomControllerProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  test(
    'openRoom resolves alias restores ticket and applies hello snapshot',
    () async {
      credentials.tickets['room-id'] = 'saved-ticket';

      await controller.openRoom('listen');
      factory.last.emitHello();
      await pumpEventQueue();

      expect(api.lastGetRoomRef, 'listen');
      expect(factory.roomIds, ['room-id']);
      expect(factory.tickets, ['saved-ticket']);
      expect(controller.state.activeRoomId, 'room-id');
      expect(controller.state.snapshot?.room.id, 'room-id');
      expect(controller.state.member?.id, 'member-id');
      expect(controller.state.status, RoomConnectionStatus.open);
    },
  );

  for (final (first, second) in [
    ('listen', 'room-id'),
    ('room-id', 'listen'),
  ]) {
    test(
      'opening "$second" after "$first" keeps the same room session',
      () async {
        credentials.tickets['room-id'] = 'saved-ticket';
        await controller.openRoom(first);
        factory.last
          ..emitHello()
          ..emit(const RoomEventReceived(_chat));
        await pumpEventQueue();
        final snapshot = controller.state.snapshot;

        await controller.openRoom(second);

        expect(factory.transports, hasLength(1));
        expect(factory.last.stopCalls, 0);
        expect(controller.state.snapshot, same(snapshot));
        expect(controller.state.notices, hasLength(1));
        expect(controller.state.status, RoomConnectionStatus.open);
      },
    );
  }

  test('openRoom creates missing identity and room ticket', () async {
    await controller.openRoom('listen');

    expect(api.createMemberCalls, 1);
    expect(api.createTicketCalls, 1);
    expect(factory.tickets, ['ticket-for-room-id']);
  });

  test('unauthorized close deletes ticket and requires authorization before rejoin', () async {
    credentials.tickets['room-id'] = 'expired-ticket';
    await controller.openRoom('listen');

    factory.last.disconnect(code: 4401);
    await pumpEventQueue();

    expect(controller.state.failure, RoomFailure.authorization);
    expect(credentials.tickets['room-id'], isNull);
    await controller.openRoom('listen');
    expect(api.createTicketCalls, 1);
    expect(factory.tickets.last, 'ticket-for-room-id');
  });

  test(
    'an openRoom left while its connection starts ends as replaced',
    () async {
      credentials.tickets['room-id'] = 'saved-ticket';
      final starting = factory.startGate = Completer<void>();
      final joining = controller.openRoom('listen');
      await pumpEventQueue();
      expect(factory.last.startCalls, 1);

      await controller.leaveRoom();
      starting.complete();
      final result = await joining;

      expect(result, isA<RoomJoinFailed>());
      expect(controller.state.activeRoomId, isNull);
      expect(factory.last.stopped, isTrue);
    },
  );

  test(
    'fast room switches stop the old owner and ignore its late hello',
    () async {
      api.rooms = [
        roomListing(id: 'room-one', slug: 'one'),
        roomListing(id: 'room-two', slug: 'two'),
      ];
      credentials.tickets['room-one'] = 'ticket-one';
      credentials.tickets['room-two'] = 'ticket-two';
      await controller.openRoom('one');
      final oldTransport = factory.last;
      await controller.openRoom('two');

      oldTransport.emitHello();
      await pumpEventQueue();

      expect(oldTransport.stopCalls, 1);
      expect(controller.state.activeRoomId, 'room-two');
      expect(controller.state.snapshot, isNull);
      factory.last.emitHello();
      await pumpEventQueue();
      expect(controller.state.activeRoomId, 'room-two');
      expect(controller.state.snapshot, isNotNull);
    },
  );

  group('cancelOpen', () {
    late FakeRoomTransport active;
    late RoomSnapshot snapshot;

    // 房间一已进入并连上，房间二正在进入。
    setUp(() async {
      api.rooms = [
        roomListing(id: 'room-one', slug: 'one'),
        roomListing(id: 'room-two', slug: 'two', name: '另一个房间'),
      ];
      credentials.tickets['room-one'] = 'ticket-one';
      credentials.tickets['room-two'] = 'ticket-two';
      await controller.openRoom('one');
      active = factory.last..emitHello();
      await pumpEventQueue();
      snapshot = controller.state.snapshot!;
    });

    void expectOneStillActive() {
      expect(active.stopCalls, 0);
      expect(factory.transports, hasLength(1));
      expect(controller.state.activeRoomId, 'room-one');
      expect(controller.state.snapshot, same(snapshot));
      expect(controller.state.status, RoomConnectionStatus.open);
      expect(controller.state.failure, isNull);
    }

    test('a room still being looked up is not entered, and the active room '
        'keeps running', () async {
      final lookup = api.getRoomGate = Completer<void>();
      final opening = controller.beginOpen('two');
      await pumpEventQueue();
      expect(api.lastGetRoomRef, 'two');

      controller.cancelOpen(opening.attempt);
      lookup.complete();
      final result = await opening.result;

      expect(result, isA<RoomJoinFailed>());
      expect(api.createTicketCalls, 0);
      expectOneStillActive();
    });

    test('a room whose ticket is being obtained is not entered', () async {
      credentials.tickets.remove('room-two');
      late final int attempt;
      api.onCreateTicket = () => controller.cancelOpen(attempt);

      final opening = controller.beginOpen('two');
      attempt = opening.attempt;
      final result = await opening.result;

      expect(result, isA<RoomJoinFailed>());
      expect(api.createTicketCalls, 1);
      expectOneStillActive();
    });

    test('a failure of the cancelled attempt does not replace the active '
        'room either', () async {
      final lookup = api.getRoomGate = Completer<void>();
      api.getRoomError = const ApiException(
        code: 'NOT_FOUND',
        message: '房间不存在',
        status: 404,
      );
      final opening = controller.beginOpen('two');
      await pumpEventQueue();

      controller.cancelOpen(opening.attempt);
      lookup.complete();
      await opening.result;

      expectOneStillActive();
    });

    test('only the attempt named is cancelled: another caller entering the '
        'same room goes on', () async {
      final lookup = api.getRoomGate = Completer<void>();
      final page = controller.beginOpen('two');
      // 模拟加入面板带房间密码进入同一个房间。
      final sheet = controller.beginOpen('two', password: 'secret');
      await pumpEventQueue();

      controller.cancelOpen(page.attempt);
      lookup.complete();

      expect(await page.result, isA<RoomJoinFailed>(), reason: 'taken over');
      expect(await sheet.result, isA<RoomJoined>());
      expect(controller.state.activeRoomId, 'room-two');
      expect(active.stopCalls, 1);
    });

    test(
      'a cancel of an attempt that is over leaves a later one alone',
      () async {
        api.ticketError = const ApiException(
          code: 'UNAUTHORIZED',
          message: '房间密码错误',
          status: 401,
        );
        credentials.tickets.remove('room-two');
        final first = controller.beginOpen('two');
        expect(await first.result, isA<RoomJoinFailed>());
        expectOneStillActive();

        api.ticketError = null;
        credentials.tickets['room-two'] = 'ticket-two';
        final lookup = api.getRoomGate = Completer<void>();
        final second = controller.beginOpen('two');
        await pumpEventQueue();
        controller.cancelOpen(first.attempt);
        lookup.complete();

        expect(await second.result, isA<RoomJoined>());
        expect(controller.state.activeRoomId, 'room-two');
      },
    );

    test('once the room is being entered it is entered, as before', () async {
      final starting = factory.startGate = Completer<void>();
      final opening = controller.beginOpen('two');
      await pumpEventQueue();
      expect(factory.transports, hasLength(2));

      controller.cancelOpen(opening.attempt);
      starting.complete();
      final result = await opening.result;

      expect(result, isA<RoomJoined>());
      expect(active.stopCalls, 1);
      expect(factory.last.stopCalls, 0);
      expect(controller.state.activeRoomId, 'room-two');
      expect(controller.state.roomName, '另一个房间');
    });
  });

  for (final (name, failure, arrange)
      in <(String, RoomFailure, void Function(FakeAlistenApi))>[
        (
          'a wrong password',
          RoomFailure.authorization,
          (api) => api.ticketError = const ApiException(
            code: 'UNAUTHORIZED',
            message: '房间密码错误',
            status: 401,
          ),
        ),
        (
          'a missing room',
          RoomFailure.notFound,
          (api) => api.getRoomError = const ApiException(
            code: 'NOT_FOUND',
            message: '房间不存在',
            status: 404,
          ),
        ),
        (
          'a network failure',
          RoomFailure.unavailable,
          (api) => api.getRoomError = const ApiException(
            code: LocalErrorCodes.network,
            message: '网络请求失败，请检查网络后重试。',
            status: null,
          ),
        ),
      ]) {
    test(
      'entering another room fails with $name and keeps the active room',
      () async {
        api.rooms = [
          roomListing(id: 'room-one', slug: 'one'),
          roomListing(id: 'room-two', slug: 'two'),
        ];
        credentials.tickets['room-one'] = 'ticket-one';
        await controller.openRoom('one');
        final active = factory.last..emitHello();
        await pumpEventQueue();
        final snapshot = controller.state.snapshot;
        expect(snapshot, isNotNull);

        arrange(api);
        final result = await controller.openRoom('two');

        expect(result, isA<RoomJoinFailed>());
        expect((result as RoomJoinFailed).failure, failure);
        expect(active.stopCalls, 0);
        expect(factory.transports, hasLength(1));
        expect(controller.state.activeRoomId, 'room-one');
        expect(controller.state.snapshot, same(snapshot));
        expect(controller.state.failure, isNull);
        expect(controller.state.status, RoomConnectionStatus.open);
        expect(lastRoom.room, 'room-one');

        api.ticketError = null;
        api.getRoomError = null;
        credentials.tickets['room-two'] = 'ticket-two';
        expect(await controller.openRoom('two'), isA<RoomJoined>());
        expect(active.stopCalls, 1);
        expect(controller.state.activeRoomId, 'room-two');
      },
    );
  }

  test(
    'event gaps request a snapshot and notices stay within the room session',
    () async {
      credentials.tickets['room-id'] = 'saved-ticket';
      await controller.openRoom('listen');
      factory.last.emitHello();

      factory.last.emit(
        const RoomEventReceived(
          SettingsUpdatedEvent(term: 1, seq: 3, playMode: RoomPlayMode.random),
        ),
      );
      await pumpEventQueue();

      expect(factory.last.syncCalls, 1);
      factory.last.emit(
        const RoomEventReceived(
          ChatMessageEvent(
            term: 1,
            seq: 4,
            member: testMember,
            content: '你好',
            sentAtMs: 123,
          ),
        ),
      );
      await pumpEventQueue();
      expect(controller.state.notices.single, isA<ChatMessageEvent>());

      await controller.leaveRoom();
      expect(controller.state.notices, isEmpty);
      expect(factory.last.stopCalls, 1);
    },
  );

  test('events dropped during a sync are fetched by one more sync', () async {
    credentials.tickets['room-id'] = 'saved-ticket';
    await controller.openRoom('listen');
    final transport = factory.last..holdSyncs = true;
    transport.emitHello();
    transport.emit(
      const RoomEventReceived(
        SettingsUpdatedEvent(term: 1, seq: 3, playMode: RoomPlayMode.random),
      ),
    );
    await pumpEventQueue();
    expect(transport.syncCalls, 1);

    transport.emit(
      const RoomEventReceived(
        SettingsUpdatedEvent(term: 1, seq: 4, playMode: RoomPlayMode.rotation),
      ),
    );
    transport.answerSync(testRoomSnapshot(seq: 3));
    await pumpEventQueue();

    expect(transport.syncCalls, 2);
    transport.answerSync(testRoomSnapshot(seq: 4));
    await pumpEventQueue();
    expect(controller.state.snapshot?.seq, 4);
    expect(transport.syncCalls, 2);
  });

  test('a gap seen just as a sync finishes is synchronised too', () async {
    credentials.tickets['room-id'] = 'saved-ticket';
    await controller.openRoom('listen');
    final transport = factory.last..emitHello();
    await pumpEventQueue();
    // 快照到达与同步循环恢复之间只隔几个微任务，缺口事件依次在每一处送达。
    var seq = 1;
    for (var delay = 0; delay < 6; delay++) {
      transport.holdSyncs = true;
      transport.emit(RoomEventReceived(_settings(seq + 2)));
      await pumpEventQueue();
      transport
        ..holdSyncs = false
        ..nextSnapshot = testRoomSnapshot(seq: seq + 4)
        ..answerSync(testRoomSnapshot(seq: seq + 2));
      _afterMicrotasks(
        delay,
        () => transport.emit(RoomEventReceived(_settings(seq + 4))),
      );
      await pumpEventQueue();
      transport.emit(RoomEventReceived(_settings(seq + 5)));
      await pumpEventQueue();

      expect(controller.state.snapshot?.seq, seq + 5, reason: 'delay $delay');
      seq += 5;
    }
  });

  test('duplicate and chat events keep the snapshot and equal states do not notify', () async {
    credentials.tickets['room-id'] = 'saved-ticket';
    await controller.openRoom('listen');
    factory.last.emitHello();
    await pumpEventQueue();
    final snapshot = controller.state.snapshot;
    var notifications = 0;
    container.listen(roomControllerProvider, (_, _) => notifications++);

    factory.last
      ..emit(RoomEventReceived(_settings(1)))
      ..emit(const RoomConnectionChanged(RoomConnectionStatus.open));
    await pumpEventQueue();
    expect(notifications, 0);

    factory.last.emit(const RoomEventReceived(_chat));
    await pumpEventQueue();
    expect(notifications, 1);
    expect(controller.state.snapshot, same(snapshot));
  });

  test(
    'foreground resume restarts the clock estimate without losing serverNow',
    () async {
      credentials.tickets['room-id'] = 'saved-ticket';
      await controller.openRoom('listen');
      final transport = factory.last..emitHello(null, 2000000);
      await pumpEventQueue();
      transport.clock.addSample(1000000, 1000000, 2000000);
      final generation = transport.clock.generation;

      await controller.handleLifecycle(AppLifecycleState.resumed);

      expect(transport.clock.generation, greaterThan(generation));
      expect(controller.serverNow, 2000000);
      expect(transport.probeCalls, 1);
      expect(transport.syncCalls, 0);
    },
  );

  test(
    'last room restoration is explicit and uses the saved room id',
    () async {
      lastRoom.room = 'listen';
      credentials.tickets['room-id'] = 'saved-ticket';

      await controller.restoreLastRoom();

      expect(api.lastGetRoomRef, 'listen');
      expect(factory.roomIds, ['room-id']);
    },
  );

  test('leaving the room stops it and forgets the last room', () async {
    credentials.tickets['room-id'] = 'saved-ticket';
    await controller.openRoom('listen');
    factory.last.emitHello();
    await pumpEventQueue();
    expect(lastRoom.room, 'room-id');

    await controller.leaveRoom();

    expect(lastRoom.room, isNull);
    expect(controller.state.status, RoomConnectionStatus.stopped);
    expect(controller.state.snapshot, isNull);
    expect(factory.last.stopCalls, 1);
  });

  test('a room left while it is looked up is replaced and gets no '
      'ticket', () async {
    final lookup = api.getRoomGate = Completer<void>();
    final opening = controller.openRoom('room-a');
    await pumpEventQueue();

    await controller.leaveRoom();
    lookup.complete();

    expect(
      await opening,
      isA<RoomJoinFailed>().having((r) => r.message, 'message', contains('取代')),
    );
    expect(credentials.writtenTickets, isEmpty);
    expect(api.createTicketCalls, 0);
    expect(factory.transports, isEmpty);
  });

  test('no room is entered while the server changes, and rooms are entered '
      'again once the change ends', () async {
    credentials.tickets['room-id'] = 'saved-ticket';
    await controller.openRoom('listen');
    lastRoom.room = 'listen';
    final changing = Completer<String>();
    final refused = <RoomJoin>[];
    late RoomState before;

    final change = controller.leaveForServerChange(() async {
      before = controller.state;
      refused
        ..add(await controller.beginOpen('listen').result)
        ..add(await controller.openRoom('other'));
      await controller.restoreLastRoom();
      expect(controller.state, same(before));
      return changing.future;
    });
    await pumpEventQueue();

    expect(factory.last.stopCalls, 1);
    expect(before.activeRoomId, isNull);
    expect(refused, [
      for (var i = 0; i < 2; i++)
        isA<RoomJoinFailed>()
            .having((r) => r.failure, 'failure', RoomFailure.unavailable)
            .having((r) => r.message, 'message', '正在切换服务器，请稍候。'),
    ]);
    expect(api.getRoomCalls, 1);
    expect(factory.transports, hasLength(1));

    changing.complete('changed');
    expect(await change, 'changed');
    expect(await controller.openRoom('listen'), isA<RoomJoined>());
    expect(factory.transports, hasLength(2));
  });

  test('rooms are entered again after a server change that failed', () async {
    await expectLater(
      controller.leaveForServerChange<void>(
        () async => throw StateError('not changed'),
      ),
      throwsStateError,
    );

    expect(await controller.openRoom('listen'), isA<RoomJoined>());
  });

  test('a room that no longer exists is forgotten', () async {
    credentials.tickets['room-id'] = 'saved-ticket';
    await controller.openRoom('listen');
    factory.last.emitHello();
    await pumpEventQueue();

    factory.last.disconnect(code: 4404);
    await pumpEventQueue();

    expect(controller.state.failure, RoomFailure.notFound);
    expect(controller.state.snapshot, isNull);
    expect(lastRoom.room, isNull);
  });

  group('while the server changes', () {
    late FakeAlistenApi apiB;
    late FakeCredentialStore storeA;
    late FakeCredentialStore storeB;
    late FakeLastRoomStore lastRoomA;
    late FakeLastRoomStore lastRoomB;
    late List<String> connected;
    late ProviderContainer switching;
    late RoomController rooms;

    // API、凭据、最近房间和房间连接都跟随 [_serverProvider]；每次连接记为
    // “服务器 票据”。
    setUp(() {
      apiB = FakeAlistenApi()..rooms = [roomListing()];
      storeA = FakeCredentialStore();
      storeB = FakeCredentialStore();
      lastRoomA = FakeLastRoomStore();
      lastRoomB = FakeLastRoomStore();
      connected = [];
      final apis = {'a': api, 'b': apiB};
      final stores = {'a': storeA, 'b': storeB};
      final lastRooms = {'a': lastRoomA, 'b': lastRoomB};
      switching = ProviderContainer(
        overrides: [
          alistenApiProvider.overrideWith(
            (ref) => apis[ref.watch(_serverProvider)]!,
          ),
          credentialStoreProvider.overrideWith(
            (ref) => stores[ref.watch(_serverProvider)]!,
          ),
          lastRoomStoreProvider.overrideWith(
            (ref) => lastRooms[ref.watch(_serverProvider)]!,
          ),
          roomTransportFactoryProvider.overrideWith((ref) {
            final server = ref.watch(_serverProvider);
            return (roomId, ticket) {
              connected.add('$server $ticket');
              return factory(roomId, ticket);
            };
          }),
          connectivityStatusProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
          clearLocalEmailProvider.overrideWithValue(() async {}),
        ],
      );
      addTearDown(switching.dispose);
      rooms = switching.read(roomControllerProvider.notifier);
    });

    void switchToB() => switching.read(_serverProvider.notifier).switchTo('b');

    void expectNoTicketAnywhere() {
      expect(api.createTicketCalls, 0);
      expect(apiB.createTicketCalls, 0);
      expect(storeA.writtenTickets, isEmpty);
      expect(storeB.writtenTickets, isEmpty);
      expect(connected, isEmpty);
    }

    test('a room keeps the server it was opened on for its ticket and its '
        'connection', () async {
      storeA.tickets['room-id'] = 'ticket-a';
      storeB.tickets['room-id'] = 'ticket-b';
      final lookup = api.getRoomGate = Completer<void>();

      final opening = rooms.openRoom('listen');
      switchToB();
      lookup.complete();

      expect(await opening, isA<RoomJoined>());
      expect(connected, ['a ticket-a']);
      expect(apiB.getRoomCalls, 0);
    });

    test('a room left while its saved ticket is read asks no server for a '
        'ticket', () async {
      storeA.memberToken = 'a';
      storeB.memberToken = 'b';
      final reading = storeA.readTicketGate = Completer<void>();
      final opening = rooms.openRoom('listen');
      await pumpEventQueue();

      await rooms.leaveRoom();
      switchToB();
      reading.complete();

      expect(await opening, isA<RoomJoinFailed>());
      expectNoTicketAnywhere();
    });

    test('a room left while its member is created asks no server for a '
        'ticket', () async {
      final creating = api.createMemberGate = Completer<void>();
      final opening = rooms.openRoom('listen');
      await pumpEventQueue();
      expect(api.createMemberCalls, 1);

      await rooms.leaveRoom();
      switchToB();
      creating.complete();

      expect(await opening, isA<RoomJoinFailed>());
      expectNoTicketAnywhere();
    });

    test('a ticket is asked for and kept on the server the room was opened '
        'on', () async {
      storeA.memberToken = 'a';
      storeB.memberToken = 'b';
      final reading = storeA.readTicketGate = Completer<void>();
      final opening = rooms.openRoom('listen');
      await pumpEventQueue();

      switchToB();
      reading.complete();

      expect(await opening, isA<RoomJoined>());
      // 身份控制器按当前服务器确认成员：不经切换器改写当前服务器时，确认落在 B
      // 上；经切换器时会先离开房间，这次尝试随即作废。
      expect(api.getMeCalls, 0);
      expect(apiB.getMeCalls, 1);
      expect(api.createTicketCalls, 1);
      expect(apiB.createTicketCalls, 0);
      expect(storeA.writtenTickets, ['room-id']);
      expect(storeB.writtenTickets, isEmpty);
      expect(connected, ['a ticket-for-room-id']);
    });

    test('a ticket refused after leaving for another server replaces no '
        'identity there', () async {
      storeA.memberToken = 'a';
      api.ticketError = unauthorized;
      api.onCreateTicket = () {
        api.getMeError = unauthorized;
        unawaited(rooms.leaveRoom());
        switchToB();
      };

      expect(await rooms.openRoom('listen'), isA<RoomJoinFailed>());
      await pumpEventQueue();

      expect(apiB.createMemberCalls + apiB.getMeCalls, 0);
      expect(storeB.memberToken, isNull);
      expect(storeB.deleteMemberCalls, 0);
      expect(storeA.memberToken, 'a');
    });

    test('a member found rejected only after leaving for another server is not '
        'replaced there', () async {
      storeA.memberToken = 'a';
      api.ticketError = unauthorized;
      final checking = Completer<Member>();
      api.onCreateTicket = () => api.getMeResult = checking;
      final opening = rooms.openRoom('listen');
      await pumpEventQueue();
      expect(api.getMeCalls, 2);

      await rooms.leaveRoom();
      switchToB();
      checking.completeError(unauthorized);

      expect(await opening, isA<RoomJoinFailed>());
      await pumpEventQueue();
      expect(apiB.createMemberCalls + apiB.getMeCalls, 0);
      expect(storeB.memberToken, isNull);
      expect(storeA.memberToken, 'a');
    });

    test('a ticket the room refuses after the switch is deleted on the server '
        'of the room', () async {
      storeA.tickets['room-id'] = 'ticket-a';
      storeB.tickets['room-id'] = 'ticket-b';
      await rooms.openRoom('listen');
      factory.last.emitHello();
      await pumpEventQueue();

      switchToB();
      factory.last.disconnect(code: 4401);
      await pumpEventQueue();

      expect(storeA.tickets, isEmpty);
      expect(storeB.tickets, {'room-id': 'ticket-b'});
    });

    test('the last room is remembered and forgotten on the server of the '
        'room', () async {
      storeA.tickets['room-id'] = 'ticket-a';
      await rooms.openRoom('listen');

      switchToB();
      factory.last.emitHello();
      await pumpEventQueue();
      expect(lastRoomA.room, 'room-id');
      expect(lastRoomB.room, isNull);

      lastRoomB.room = 'room-id';
      factory.last.disconnect(code: 4404);
      await pumpEventQueue();
      expect(lastRoomA.room, isNull);
      expect(lastRoomB.room, 'room-id');
    });

    test('a room refused by its server is forgotten there, not on the server '
        'switched to', () async {
      lastRoomA.room = 'listen';
      lastRoomB.room = 'listen';
      final lookup = api.getRoomGate = Completer<void>();
      api.getRoomError = const ApiException(
        code: 'NOT_FOUND',
        message: '房间不存在',
        status: 404,
      );
      final opening = rooms.openRoom('listen');

      switchToB();
      lookup.complete();

      expect(await opening, isA<RoomJoinFailed>());
      await pumpEventQueue();
      expect(lastRoomA.room, isNull);
      expect(lastRoomB.room, 'listen');
    });

    test('leaving a room after the switch forgets it on its own '
        'server', () async {
      storeA.tickets['room-id'] = 'ticket-a';
      await rooms.openRoom('listen');
      factory.last.emitHello();
      await pumpEventQueue();

      switchToB();
      lastRoomB.room = 'room-id';
      await rooms.leaveRoom();

      expect(lastRoomA.room, isNull);
      expect(lastRoomB.room, 'room-id');
    });
  });
}

final _serverProvider = NotifierProvider<_Server, String>(_Server.new);

final class _Server extends Notifier<String> {
  @override
  String build() => 'a';

  void switchTo(String server) => state = server;
}

SettingsUpdatedEvent _settings(int seq) {
  return SettingsUpdatedEvent(
    term: 1,
    seq: seq,
    playMode: RoomPlayMode.values[seq % RoomPlayMode.values.length],
  );
}

void _afterMicrotasks(int count, void Function() action) {
  if (count == 0) {
    action();
    return;
  }
  scheduleMicrotask(() => _afterMicrotasks(count - 1, action));
}

const _chat = ChatMessageEvent(
  term: 1,
  seq: 2,
  member: testMember,
  content: '你好',
  sentAtMs: 1,
);
