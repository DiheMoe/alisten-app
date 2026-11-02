import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/application/room_controller.dart';
import 'package:alisten/features/room/application/room_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../room_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late FakeRoomTransportFactory factory;
  late ProviderContainer container;
  late RoomController controller;

  setUp(() async {
    api = FakeAlistenApi()..rooms = [roomListing()];
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
    controller = container.read(roomControllerProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  test('join failure is visible without creating a transport', () async {
    api.ticketError = const ApiException(
      code: 'UNAUTHORIZED',
      message: '票据失效',
      status: 401,
    );

    await controller.openRoom('listen');

    expect(controller.state.failure, RoomFailure.authorization);
    expect(controller.state.errorMessage, isNotNull);
    expect(factory.transports, isEmpty);
  });

  test('a refusal carries the room found before it, and none when the room '
      'itself could not be looked up', () async {
    api.ticketError = const ApiException(
      code: 'UNAUTHORIZED',
      message: '需要房间密码',
      status: 401,
    );

    final refused = await controller.openRoom('listen');
    expect(
      refused,
      isA<RoomJoinFailed>().having((r) => r.room?.id, 'room', 'room-id'),
    );

    api.getRoomError = const ApiException(
      code: 'UNAUTHORIZED',
      message: '需要验证',
      status: 401,
    );
    final unresolved = await controller.openRoom('other');
    expect(
      unresolved,
      isA<RoomJoinFailed>().having((r) => r.room, 'room', isNull),
    );
  });

  test(
    'a refused ticket replaces the identity only when the member is rejected',
    () async {
      credentials.memberToken = 'stored-token';
      api.ticketError = const ApiException(
        code: 'UNAUTHORIZED',
        message: '房间密码错误',
        status: 401,
      );

      await controller.openRoom('listen');

      expect(controller.state.errorMessage, '房间密码错误');
      expect(api.createMemberCalls, 0);
      expect(credentials.memberToken, 'stored-token');

      api.onCreateTicket = () => api.getMeError = unauthorized;
      await controller.openRoom('listen');

      expect(controller.state.failure, RoomFailure.authorization);
      expect(api.createTicketCalls, 2, reason: 'the refusal is not replayed');
      expect(api.createMemberCalls, 1);
      expect(credentials.memberToken, 'new-member-token');
      expect(
        container.read(identityControllerProvider).notice,
        identityRenewedNotice,
      );
      expect(factory.transports, isEmpty);
    },
  );

  test('REST room not found maps to a non-retryable room failure', () async {
    api.getRoomError = const ApiException(
      code: 'NOT_FOUND',
      message: '房间不存在',
      status: 404,
    );

    await controller.openRoom('listen');

    expect(controller.state.failure, RoomFailure.notFound);
    expect(factory.transports, isEmpty);
  });

  test(
    'a room that stopped is still named, though its snapshot is gone',
    () async {
      credentials.tickets['room-id'] = 'saved-ticket';
      await controller.openRoom('listen');
      expect(controller.state.roomName, '一起听', reason: 'from the listing');
      factory.last.emitHello();
      await pumpEventQueue();
      expect(controller.state.snapshot?.room.name, '房间');

      factory.last.disconnect(code: 4404);
      await pumpEventQueue();

      expect(controller.state.failure, RoomFailure.notFound);
      expect(controller.state.snapshot, isNull);
      expect(controller.state.roomName, '房间', reason: 'the last known name');
    },
  );

  test('a refusal after the room was resolved names it', () async {
    api.ticketError = const ApiException(
      code: 'UNAUTHORIZED',
      message: '房间密码错误',
      status: 401,
    );

    await controller.openRoom('listen');

    expect(controller.state.activeRoomId, 'room-id');
    expect(controller.state.roomName, '一起听');
  });

  test('invalid argument close stops without blind reconnect', () async {
    credentials.tickets['room-id'] = 'saved-ticket';
    await controller.openRoom('listen');

    factory.last.disconnect(code: 1008);
    await pumpEventQueue();

    expect(controller.state.status, RoomConnectionStatus.stopped);
    expect(controller.state.failure, RoomFailure.unavailable);
  });

  test('the text of a refused hello is not shown by itself', () async {
    credentials.tickets['room-id'] = 'saved-ticket';
    await controller.openRoom('listen');

    factory.last.emit(
      const RoomErrorReceived(code: 'CLIENT_OUTDATED', message: '服务端的拒绝原因'),
    );
    await pumpEventQueue();

    expect(controller.state.errorMessage, isNull);
    expect(controller.state.failure, isNull);
  });

  test(
    'an outdated client keeps its upgrade message and is not retried',
    () async {
      credentials.tickets['room-id'] = 'saved-ticket';
      await controller.openRoom('listen');
      factory.last.disconnect(code: 4426);
      await pumpEventQueue();
      final message = controller.state.errorMessage;
      expect(message, contains('升级'));

      await controller.checkConnection();
      await controller.openRoom('listen');

      expect(controller.state.failure, RoomFailure.outdated);
      expect(controller.state.errorMessage, message);
      expect(controller.state.snapshot, isNull);
      expect(factory.transports, hasLength(1));
    },
  );

  test('an undecodable snapshot stops the room as outdated', () async {
    credentials.tickets['room-id'] = 'saved-ticket';
    await controller.openRoom('listen');
    final transport = factory.last..emitHello();
    transport.syncError = RoomRequestException.undecodable('room.sync');

    transport.emit(
      const RoomEventReceived(
        SettingsUpdatedEvent(term: 1, seq: 3, playMode: RoomPlayMode.random),
      ),
    );
    await pumpEventQueue();

    expect(controller.state.failure, RoomFailure.outdated);
    expect(controller.state.status, RoomConnectionStatus.stopped);
    expect(controller.state.snapshot, isNull);
    expect(transport.stopped, isTrue);
    expect(transport.syncCalls, 1);
  });

  test(
    'a failed sync neither restarts the connection nor replays mutations',
    () async {
      credentials.tickets['room-id'] = 'saved-ticket';
      await controller.openRoom('listen');
      final transport = factory.last..emitHello();
      transport.syncError = const RoomRequestException(
        code: 'UNAVAILABLE',
        message: '服务暂时不可用',
        outcome: RoomRequestOutcome.failed,
      );

      transport.emit(
        const RoomEventReceived(
          SettingsUpdatedEvent(term: 1, seq: 3, playMode: RoomPlayMode.random),
        ),
      );
      await pumpEventQueue();

      expect(transport.syncCalls, 1);
      expect(transport.restartCalls, 0);
      expect(transport.requests, isEmpty);
      expect(controller.state.failure, isNull);
    },
  );
}
