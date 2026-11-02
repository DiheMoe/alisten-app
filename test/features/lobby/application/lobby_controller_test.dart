import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/lobby/application/lobby_controller.dart';
import 'package:alisten/features/room/application/room_controller.dart';
import 'package:alisten/features/room/application/room_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../room/room_test_doubles.dart';
import '../lobby_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late FakeRoomTransportFactory factory;
  late ProviderContainer container;
  late LobbyController controller;

  setUp(() async {
    api = FakeAlistenApi();
    credentials = FakeCredentialStore();
    factory = FakeRoomTransportFactory();
    container = ProviderContainer(
      overrides: [
        alistenApiProvider.overrideWithValue(api),
        credentialStoreProvider.overrideWithValue(credentials),
        roomTransportFactoryProvider.overrideWithValue(factory.call),
        ...roomDeviceOverrides(),
        clearLocalEmailProvider.overrideWithValue(() async {}),
      ],
    );
    controller = container.read(lobbyControllerProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  test('load exposes rooms and filter matches name and description case-insensitively', () async {
    api.rooms = [
      roomListing(name: 'Jazz Night', description: '安静欣赏'),
      roomListing(id: 'other', name: '其他', description: 'JAZZ 爱好者'),
      roomListing(id: 'third', name: '摇滚', description: '现场'),
    ];

    await controller.load();
    controller.filter('  jazz ');

    expect(controller.state.rooms, hasLength(3));
    expect(controller.state.query, '  jazz ');
    expect(controller.state.filteredRooms.map((room) => room.id), [
      'room-id',
      'other',
    ]);
  });

  test('load error is visible and retry replaces it with data', () async {
    api.listError = const FormatException('bad response');

    await controller.load();

    expect(controller.state.loading, isFalse);
    expect(controller.state.listError, isNotNull);

    api.listError = null;
    api.rooms = [roomListing()];
    await controller.load();

    expect(controller.state.listError, isNull);
    expect(controller.state.filteredRooms, hasLength(1));
  });

  test('a load answered late does not replace the newer result', () async {
    final first = Completer<List<RoomListing>>();
    final second = Completer<List<RoomListing>>();
    final answers = [first, second];
    api.listRoomsHandler = () => answers.removeAt(0).future;

    final older = controller.load();
    final newer = controller.load();
    second.complete([roomListing(id: 'newer')]);
    await newer;
    first.complete([roomListing(id: 'older')]);
    await older;

    expect(controller.state.rooms.map((room) => room.id), ['newer']);
    expect(controller.state.loading, isFalse);
  });

  test('join enters the room through the room owner', () async {
    api.rooms = [roomListing(hasPassword: true)];

    final room = await controller.join('room-id', password: 'secret');

    expect(room.id, 'room-id');
    expect(api.lastGetRoomRef, 'room-id');
    expect(api.createMemberCalls, 1);
    expect(api.createTicketCalls, 1);
    expect(credentials.tickets['room-id'], 'ticket-for-room-id');
    expect(factory.tickets, ['ticket-for-room-id']);
    expect(controller.state.busy, isFalse);
  });

  test('a password is asked for only by a room that has one and whose '
      'ticket is not held', () async {
    credentials.tickets['held'] = 'ticket';

    expect(await controller.needsPassword(roomListing()), isFalse);
    expect(
      await controller.needsPassword(roomListing(hasPassword: true)),
      isTrue,
    );
    expect(
      await controller.needsPassword(
        roomListing(id: 'held', hasPassword: true),
      ),
      isFalse,
    );
    // 房间资料不详时，只能假定它需要密码。
    expect(await controller.needsPassword(null), isTrue);
  });

  test('a join that breaks unexpectedly has an unknown result, logged by '
      'its type alone', () async {
    final records = <(String, int, String)>[];
    AppLog.onRecord = (name, level, message) =>
        records.add((name, level, message));
    addTearDown(() => AppLog.onRecord = null);
    api.rooms = [roomListing()];
    final start = factory.startGate = Completer<void>();

    final joining = controller.join('room-id');
    await pumpEventQueue();
    start.completeError(StateError('ticket-for-room-id'));

    await expectLater(
      joining,
      throwsA(
        isA<LobbyActionException>()
            .having((e) => e.unknown, 'unknown', isTrue)
            .having((e) => e.failure, 'failure', null),
      ),
    );
    expect(controller.state.busy, isFalse);
    final errors = [
      for (final record in records)
        if (record.$2 >= 1000) record,
    ];
    expect(errors.map((record) => record.$1), ['alisten.lobby']);
    expect(errors.where((record) => record.$3.contains('ticket')), isEmpty);
  });

  test('a refused join says why and leaves the room list alone', () async {
    api.listError = const FormatException('bad response');
    await controller.load();
    final listError = controller.state.listError;
    expect(listError, isNotNull);
    api.rooms = [roomListing(hasPassword: true)];
    api.ticketError = const ApiException(
      code: 'UNAUTHORIZED',
      message: '房间密码错误',
      status: 401,
    );

    await expectLater(
      controller.join('listen', password: 'wrong'),
      throwsA(
        isA<LobbyActionException>()
            .having((e) => e.failure, 'failure', RoomFailure.authorization)
            .having((e) => e.message, 'message', '房间密码错误')
            .having((e) => e.unknown, 'unknown', isFalse),
      ),
    );

    expect(controller.state.listError, listError);
    expect(controller.state.busy, isFalse);

    api.ticketError = null;
    final room = await controller.join('listen', password: 'right');
    expect(room.id, 'room-id');
  });

  test('concurrent joins of one room exchange a single ticket', () async {
    api.rooms = [roomListing()];
    api.createMemberGate = Completer<void>();

    final first = controller.join('listen');
    final second = controller.join('listen');
    await pumpEventQueue();
    api.createMemberGate!.complete();
    final rooms = await Future.wait([first, second]);

    expect(rooms.map((room) => room.id), ['room-id', 'room-id']);
    expect(api.createTicketCalls, 1);
    expect(factory.transports, hasLength(1));
  });

  test('submitting again after a failed join only joins', () async {
    api.ticketError = const ApiException(
      code: 'UNAUTHORIZED',
      message: '房间密码错误',
      status: 401,
    );

    await expectLater(
      controller.createRoom(name: '新房间', description: '描述', password: 'x'),
      throwsA(isA<LobbyActionException>()),
    );
    api.ticketError = null;
    final room = await controller.createRoom(
      name: '新房间',
      description: '描述',
      password: 'x',
    );

    expect(room.id, 'created-room-id');
    expect(api.createRoomCalls, 1);
    expect(api.createTicketCalls, 2);

    await controller.createRoom(name: '另一个房间', description: '描述');
    expect(api.createRoomCalls, 2);
  });

  test(
    'a room creation without an answer is not retried and refreshes the list',
    () async {
      final refresh = Completer<List<RoomListing>>();
      api.listRoomsHandler = () => refresh.future;
      api.createRoomError = const ApiException(
        code: LocalErrorCodes.network,
        message: '请求超时，请检查网络后重试。',
        status: null,
      );

      await expectLater(
        controller.createRoom(name: '新房间', description: ''),
        throwsA(
          isA<LobbyActionException>()
              .having((e) => e.failure, 'failure', null)
              .having((e) => e.unknown, 'unknown', isTrue)
              .having((e) => e.message, 'message', contains('可能已经创建')),
        ),
      );
      await pumpEventQueue();

      expect(api.createRoomCalls, 1);
      expect(api.listRoomsCalls, 1);
      expect(factory.transports, isEmpty);
      expect(controller.state.busy, isFalse);

      // 刷新后的列表确认房间是否已存在之前，不能再次创建。
      api.createRoomError = null;
      await expectLater(
        controller.createRoom(name: '新房间', description: ''),
        throwsA(
          isA<LobbyActionException>()
              .having((e) => e.unknown, 'unknown', isTrue)
              .having((e) => e.message, 'message', contains('刷新')),
        ),
      );
      expect(api.createRoomCalls, 1);

      refresh.complete([roomListing(id: 'created-room-id', name: '新房间')]);
      await pumpEventQueue();
      final room = await controller.createRoom(name: '新房间', description: '');
      expect(room.id, 'created-room-id');
      expect(api.createRoomCalls, 2);
    },
  );

  test('creating stays refused while the list could not be refreshed after '
      'a creation without an answer', () async {
    api.listError = const FormatException('offline');
    api.createRoomError = const ApiException(
      code: LocalErrorCodes.network,
      message: '请求超时，请检查网络后重试。',
      status: null,
    );
    await expectLater(
      controller.createRoom(name: '新房间', description: ''),
      throwsA(isA<LobbyActionException>()),
    );
    await pumpEventQueue();
    expect(controller.state.listError, isNotNull);

    api.createRoomError = null;
    await expectLater(
      controller.createRoom(name: '新房间', description: ''),
      throwsA(
        isA<LobbyActionException>().having((e) => e.unknown, 'unknown', isTrue),
      ),
    );
    expect(api.createRoomCalls, 1);

    api.listError = null;
    await controller.load();
    await controller.createRoom(name: '新房间', description: '');
    expect(api.createRoomCalls, 2);
  });

  // 被限流的请求未执行，房间不可能已建好。
  test('a room creation turned away for coming too often is refused, does '
      'not hold back creating and can be sent again at once', () async {
    api.createRoomError = const ApiException(
      code: 'RATE_LIMITED',
      message: '请求太频繁，请稍后再试。',
      status: 429,
    );

    await expectLater(
      controller.createRoom(name: '新房间', description: ''),
      throwsA(
        isA<LobbyActionException>()
            .having((e) => e.unknown, 'unknown', isFalse)
            .having((e) => e.message, 'message', '请求太频繁，请稍后再试。'),
      ),
    );
    await pumpEventQueue();
    expect(api.listRoomsCalls, 0);
    expect(controller.state.busy, isFalse);

    api.createRoomError = null;
    final room = await controller.createRoom(name: '新房间', description: '');
    expect(room.id, 'created-room-id');
    expect(api.createRoomCalls, 2);
  });

  test('a room creation that breaks unexpectedly has an unknown result, is '
      'logged by its type alone and refreshes the list', () async {
    final records = <(String, int, String)>[];
    AppLog.onRecord = (name, level, message) =>
        records.add((name, level, message));
    addTearDown(() => AppLog.onRecord = null);
    // 例如回复的字段类型与协议不符，此时房间可能已建好。
    api.createRoomError = const FormatException('新房间 secret');

    await expectLater(
      controller.createRoom(name: '新房间', description: '', password: 'secret'),
      throwsA(
        isA<LobbyActionException>()
            .having((e) => e.unknown, 'unknown', isTrue)
            .having((e) => e.message, 'message', contains('可能已经创建')),
      ),
    );
    await pumpEventQueue();

    expect(api.createRoomCalls, 1);
    expect(api.listRoomsCalls, 1);
    final errors = [
      for (final record in records)
        if (record.$2 >= 1000) record,
    ];
    expect(errors.map((record) => record.$1), ['alisten.lobby']);
    expect(
      errors.where(
        (record) => record.$3.contains('secret') || record.$3.contains('新房间'),
      ),
      isEmpty,
    );
  });

  test(
    'another request while one runs is refused without disturbing it',
    () async {
      api.rooms = [roomListing(), roomListing(id: 'other', slug: 'other')];
      api.createMemberGate = Completer<void>();

      final running = controller.join('listen');
      await pumpEventQueue();
      for (final attempt in [
        controller.join('other'),
        controller.createRoom(name: '新房间', description: ''),
      ]) {
        await expectLater(
          attempt,
          throwsA(
            isA<LobbyActionException>().having(
              (e) => e.failure,
              'failure',
              null,
            ),
          ),
        );
      }

      expect(controller.state.busy, isTrue);
      api.createMemberGate!.complete();
      expect((await running).id, 'room-id');
      expect(controller.state.busy, isFalse);
      expect(api.createRoomCalls, 0);
      expect(api.createTicketCalls, 1);
    },
  );

  for (final (code, failure) in [
    ('NOT_FOUND', RoomFailure.notFound),
    ('CLIENT_OUTDATED', RoomFailure.outdated),
  ]) {
    test('an explicit join enters a room that failed with $code', () async {
      final room = container.read(roomControllerProvider.notifier);
      api.getRoomError = ApiException(code: code, message: '失败', status: 404);
      await room.openRoom('listen');
      expect(container.read(roomControllerProvider).failure, failure);
      api.getRoomError = null;
      api.rooms = [roomListing()];

      final joined = await controller.join('listen');

      expect(joined.id, 'room-id');
      expect(container.read(roomControllerProvider).failure, isNull);
      expect(factory.transports, hasLength(1));
    });
  }

  group('resetForServerChange', () {
    const serverChanged = '服务器已经切换，这次操作没有完成。';

    Matcher refusedAsSwitched() => throwsA(
      isA<LobbyActionException>()
          .having((e) => e.message, 'message', serverChanged)
          .having((e) => e.failure, 'failure', null)
          .having((e) => e.unknown, 'unknown', isFalse),
    );

    Matcher createdMaybeOnOldServer() => throwsA(
      isA<LobbyActionException>()
          .having((e) => e.message, 'message', '服务器已经切换，房间可能已在原服务器上创建。')
          .having((e) => e.failure, 'failure', null)
          .having((e) => e.unknown, 'unknown', isTrue),
    );

    test('rooms listed before the reset are dropped and the filter is '
        'kept', () async {
      final first = Completer<List<RoomListing>>();
      final second = Completer<List<RoomListing>>();
      final answers = [first, second];
      api.listRoomsHandler = () => answers.removeAt(0).future;
      controller.filter('一起');
      final loading = controller.load();

      controller.resetForServerChange();
      second.complete([roomListing(id: 'b')]);
      await pumpEventQueue();
      first.complete([roomListing(id: 'a')]);
      await loading;

      expect(controller.state.rooms.map((room) => room.id), ['b']);
      expect(controller.state.query, '一起');
      expect(controller.state.loading, isFalse);
    });

    test('the rooms of the old server are cleared at once and the list is '
        'loaded again', () async {
      api.rooms = [roomListing(id: 'old')];
      await controller.load();
      api.listRoomsHandler = () => Completer<List<RoomListing>>().future;

      controller.resetForServerChange();

      expect(controller.state.rooms, isEmpty);
      expect(controller.state.loading, isTrue);
      expect(controller.state.listError, isNull);
      expect(api.listRoomsCalls, 2);
    });

    test('a room created on the old server is not entered, and the same '
        'form creates a room again', () async {
      final creating = api.createRoomGate = Completer<void>();
      final attempt = controller.createRoom(name: '新房间', description: '');
      await pumpEventQueue();

      controller.resetForServerChange();
      creating.complete();

      await expectLater(attempt, createdMaybeOnOldServer());
      expect(api.getRoomCalls, 0);
      expect(factory.transports, isEmpty);
      final room = await controller.createRoom(name: '新房间', description: '');
      expect(room.id, 'created-room-id');
      expect(api.createRoomCalls, 2);
    });

    test('a room created on the old server whose entry is interrupted by the '
        'change may exist there', () async {
      final lookup = api.getRoomGate = Completer<void>();
      final attempt = controller.createRoom(name: '新房间', description: '');
      await pumpEventQueue();
      expect(api.getRoomCalls, 1);

      await container.read(roomControllerProvider.notifier).leaveRoom();
      controller.resetForServerChange();
      lookup.complete();

      await expectLater(attempt, createdMaybeOnOldServer());
      expect(factory.transports, isEmpty);
    });

    test('a creation the old server refused says only that the server '
        'changed', () async {
      final creating = api.createRoomGate = Completer<void>();
      api.createRoomError = const ApiException(
        code: 'INVALID_ARGUMENT',
        message: '房间名称不合法',
        status: 400,
      );
      final attempt = controller.createRoom(name: '新房间', description: '');
      await pumpEventQueue();

      controller.resetForServerChange();
      creating.complete();

      await expectLater(attempt, refusedAsSwitched());
    });

    test('entering a room created by an earlier attempt, interrupted by the '
        'change, creates nothing', () async {
      api.ticketError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );
      await expectLater(
        controller.createRoom(name: '新房间', description: ''),
        throwsA(isA<LobbyActionException>()),
      );
      api.ticketError = null;
      final lookup = api.getRoomGate = Completer<void>();
      final attempt = controller.createRoom(name: '新房间', description: '');
      await pumpEventQueue();

      await container.read(roomControllerProvider.notifier).leaveRoom();
      controller.resetForServerChange();
      lookup.complete();

      await expectLater(attempt, refusedAsSwitched());
      expect(api.createRoomCalls, 1);
      expect(factory.transports, isEmpty);
    });

    test('a creation on the old server without an answer neither refreshes '
        'the list nor holds back creating on the new one', () async {
      final creating = api.createRoomGate = Completer<void>();
      api.createRoomError = const ApiException(
        code: LocalErrorCodes.network,
        message: '请求超时，请检查网络后重试。',
        status: null,
      );
      final attempt = controller.createRoom(name: '新房间', description: '');
      await pumpEventQueue();

      controller.resetForServerChange();
      creating.complete();

      await expectLater(attempt, createdMaybeOnOldServer());
      await pumpEventQueue();
      expect(api.listRoomsCalls, 1);
      api.createRoomError = null;
      await controller.createRoom(name: '新房间', description: '');
      expect(api.createRoomCalls, 2);
    });

    test('a room created but not entered on the old server is not entered '
        'from the new one', () async {
      api.ticketError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );
      await expectLater(
        controller.createRoom(name: '新房间', description: ''),
        throwsA(isA<LobbyActionException>()),
      );
      expect(api.createRoomCalls, 1);
      api.ticketError = null;

      controller.resetForServerChange();
      await controller.createRoom(name: '新房间', description: '');

      expect(api.createRoomCalls, 2);
    });

    test('a join interrupted by the server change says so', () async {
      final lookup = api.getRoomGate = Completer<void>();
      final joining = controller.join('listen');
      await pumpEventQueue();

      await container.read(roomControllerProvider.notifier).leaveRoom();
      controller.resetForServerChange();
      lookup.complete();

      await expectLater(joining, refusedAsSwitched());
      expect(factory.transports, isEmpty);
    });

    test('a join on the new server is neither refused nor marked finished '
        'by one still running on the old server', () async {
      api.rooms = [roomListing(), roomListing(id: 'other', slug: 'other')];
      final lookup = api.getRoomGate = Completer<void>();
      final old = controller.join('listen');
      await pumpEventQueue();
      await container.read(roomControllerProvider.notifier).leaveRoom();

      controller.resetForServerChange();
      expect(controller.state.busy, isFalse);
      final creating = api.createMemberGate = Completer<void>();
      final next = controller.join('other');
      expect(controller.state.busy, isTrue);
      lookup.complete();

      await expectLater(old, refusedAsSwitched());
      expect(controller.state.busy, isTrue);
      creating.complete();
      expect((await next).id, 'other');
      expect(controller.state.busy, isFalse);
    });
  });
}
