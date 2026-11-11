import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/application/room_controller.dart';
import 'package:alisten/features/room/application/room_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../room_test_doubles.dart';

const _wrongPassword = ApiException(
  code: 'INVALID_CREDENTIALS',
  message: '用户名或密码不对',
  status: 401,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late FakeRoomTransportFactory factory;
  late FakeLastRoomStore lastRoom;
  late ProviderContainer container;
  late RoomController room;
  late IdentityController identity;

  Future<SignedIn> signIn() => identity.adoptSession(
    (api) => api.login(username: 'mao', password: 'password1'),
  );

  Future<void> enter() async {
    await room.openRoom('listen');
    factory.last.emitHello();
    await pumpEventQueue();
  }

  setUp(() {
    api = FakeAlistenApi()..rooms = [roomListing()];
    credentials = FakeCredentialStore()..memberToken = 'guest-token';
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
    room = container.read(roomControllerProvider.notifier);
    identity = container.read(identityControllerProvider.notifier);
  });

  tearDown(() => container.dispose());

  test(
    'signing in re-enters the room with a ticket of the new session',
    () async {
      await enter();

      await room.changeSession(signIn);
      await pumpEventQueue();

      expect(factory.transports, hasLength(2));
      expect(factory.transports.first.stopped, isTrue);
      expect(credentials.memberToken, 'account-token');
      expect(api.createTicketCalls, 2);
      expect(room.state.activeRoomId, 'room-id');
      expect(room.state.snapshot, isNull);
      expect(lastRoom.room, 'room-id');
    },
  );

  test('a failed sign-in keeps the room playing', () async {
    await enter();
    api.loginError = _wrongPassword;

    await expectLater(room.changeSession(signIn), throwsA(isA<ApiException>()));
    await pumpEventQueue();

    expect(factory.transports, hasLength(1));
    expect(room.state.snapshot, isNotNull);
  });

  test('a 4401 during a failed sign-in is handled after it', () async {
    await enter();
    final gate = Completer<void>();
    api.loginGate = gate;
    api.loginError = _wrongPassword;

    final change = room.changeSession(signIn);
    await pumpEventQueue();
    factory.last.disconnect(code: 4401);
    await pumpEventQueue();
    expect(room.state.failure, isNull);
    expect(room.state.snapshot, isNotNull);

    gate.complete();
    await expectLater(change, throwsA(isA<ApiException>()));
    await pumpEventQueue();

    expect(room.state.failure, RoomFailure.authorization);
  });

  test(
    'a 4401 during a successful sign-in is dropped for the re-entry',
    () async {
      await enter();
      final gate = Completer<void>();
      api.loginGate = gate;

      final change = room.changeSession(signIn);
      await pumpEventQueue();
      factory.last.disconnect(code: 4401);
      await pumpEventQueue();
      gate.complete();
      await change;
      await pumpEventQueue();

      expect(factory.transports, hasLength(2));
      expect(room.state.failure, isNull);
      expect(room.state.status, RoomConnectionStatus.connecting);
    },
  );

  test('the room waits for the whole change before re-entering', () async {
    await enter();
    final gate = Completer<void>();

    final change = room.changeSession(() async {
      await signIn();
      await gate.future;
    });
    await pumpEventQueue();
    expect(factory.transports, hasLength(1));
    expect(await room.openRoom('other'), isA<RoomJoinFailed>());

    gate.complete();
    await change;
    await pumpEventQueue();
    expect(factory.transports, hasLength(2));
  });

  test(
    'a room with a password waits for its password after signing in',
    () async {
      api.rooms = [roomListing(hasPassword: true)];
      credentials.tickets['room-id'] = 'guest-ticket';
      await enter();
      api.ticketError = unauthorized;

      await room.changeSession(signIn);
      await pumpEventQueue();

      expect(room.state.failure, RoomFailure.authorization);
      expect(credentials.memberToken, 'account-token');
    },
  );

  test('a room that is gone is not entered again', () async {
    await enter();
    factory.last.disconnect(code: 4404);
    await pumpEventQueue();

    await room.changeSession(signIn);
    await pumpEventQueue();

    expect(factory.transports, hasLength(1));
    expect(room.state.failure, RoomFailure.notFound);
  });

  test('signing out re-enters as a new guest', () async {
    await enter();
    await room.changeSession(signIn);
    await pumpEventQueue();

    await room.changeSession(() => identity.signOut((api) => api.logout()));
    await pumpEventQueue();

    expect(factory.transports, hasLength(3));
    expect(credentials.memberToken, 'new-member-token');
  });

  test(
    'a session dropped elsewhere re-enters as a guest and says so',
    () async {
      credentials.memberToken = 'account-token';
      api.me = accountMember;
      api.account = const Account(username: 'mao', github: false);
      await identity.restore();
      await enter();
      api.getMeError = unauthorized;

      factory.last.disconnect(code: 4401);
      await pumpEventQueue();

      expect(
        container.read(identityControllerProvider).notice,
        signedOutNotice,
      );
      expect(factory.transports, hasLength(2));
      expect(credentials.memberToken, 'new-member-token');
    },
  );

  test('a replacement while fetching the ticket does not loop', () async {
    await enter();
    api.ticketError = unauthorized;
    api.getMeError = unauthorized;

    await room.changeSession(signIn);
    await pumpEventQueue();

    expect(api.createTicketCalls, 2);
    expect(room.state.failure, RoomFailure.authorization);
    expect(factory.transports, hasLength(1));
  });

  test('leaving for another server during a sign-in enters nothing', () async {
    await enter();
    final gate = Completer<void>();
    api.loginGate = gate;

    final change = room.changeSession(signIn);
    await pumpEventQueue();
    await room.leaveForServerChange(() async {});
    gate.complete();
    await change;
    await pumpEventQueue();

    expect(factory.transports, hasLength(1));
    expect(room.state.activeRoomId, isNull);
  });

  test('opening the room while it is entered again still connects', () async {
    await enter();
    final gate = api.getRoomGate = Completer<void>();

    await room.changeSession(signIn);
    await pumpEventQueue();
    final opening = room.openRoom('listen');
    gate.complete();

    expect(await opening, isA<RoomJoined>());
    await pumpEventQueue();
    expect(factory.transports, hasLength(2));
    expect(room.state.activeRoomId, 'room-id');
  });

  test(
    'withdrawing another room during a re-entry still enters this one',
    () async {
      await enter();
      final gate = api.getRoomGate = Completer<void>();

      await room.changeSession(signIn);
      await pumpEventQueue();
      final other = room.beginOpen('other');
      room.cancelOpen(other.attempt);
      gate.complete();

      expect(await other.result, isA<RoomJoinFailed>());
      await pumpEventQueue();
      expect(factory.transports, hasLength(2));
      expect(room.state.activeRoomId, 'room-id');
    },
  );

  test('a stop held while another room resolves is handled after a sign-in '
      'that cannot re-enter', () async {
    await enter();
    final resolving = api.getRoomGate = Completer<void>();
    final other = room.openRoom('other');
    final login = api.loginGate = Completer<void>();
    final change = room.changeSession(signIn);
    await pumpEventQueue();
    factory.last.disconnect(code: 4401);
    await pumpEventQueue();
    login.complete();
    await change;
    await pumpEventQueue();

    expect(room.state.failure, RoomFailure.authorization);
    expect(room.state.activeRoomId, 'room-id');

    api.getRoomError = const ApiException(
      code: LocalErrorCodes.network,
      message: '请求超时，请检查网络后重试。',
      status: null,
    );
    resolving.complete();

    expect(await other, isA<RoomJoinFailed>());
    expect(room.state.failure, RoomFailure.unavailable);
    expect(room.names('other'), isTrue);
  });

  test('a stop held while a withdrawn room resolves stays handled', () async {
    await enter();
    final resolving = api.getRoomGate = Completer<void>();
    final other = room.beginOpen('other');
    final login = api.loginGate = Completer<void>();
    final change = room.changeSession(signIn);
    await pumpEventQueue();
    factory.last.disconnect(code: 4401);
    await pumpEventQueue();
    login.complete();
    await change;
    await pumpEventQueue();
    room.cancelOpen(other.attempt);
    resolving.complete();

    expect(await other.result, isA<RoomJoinFailed>());
    await pumpEventQueue();
    expect(room.state.failure, RoomFailure.authorization);
    expect(room.state.activeRoomId, 'room-id');
    expect(factory.transports, hasLength(1));
  });

  test('a 4401 with a valid identity stays stopped', () async {
    await enter();
    final checks = api.getMeCalls;

    factory.last.disconnect(code: 4401);
    await pumpEventQueue();

    expect(api.getMeCalls, checks + 1);
    expect(room.state.failure, RoomFailure.authorization);
    expect(factory.transports, hasLength(1));
    expect(credentials.memberToken, 'guest-token');
  });

  test('a 4401 whose identity cannot be checked stays stopped', () async {
    await enter();
    api.getMeError = const ApiException(
      code: LocalErrorCodes.network,
      message: '请求超时，请检查网络后重试。',
      status: null,
    );

    factory.last.disconnect(code: 4401);
    await pumpEventQueue();

    expect(room.state.failure, RoomFailure.authorization);
    expect(factory.transports, hasLength(1));
    expect(credentials.memberToken, 'guest-token');
  });

  test('a stop held for a room left during a sign-in is dropped', () async {
    await enter();
    final gate = Completer<void>();
    api.loginGate = gate;
    api.loginError = _wrongPassword;

    final change = room.changeSession(signIn);
    await pumpEventQueue();
    factory.last.disconnect(code: 4401);
    await pumpEventQueue();
    await room.leaveRoom();
    gate.complete();
    await expectLater(change, throwsA(isA<ApiException>()));
    await pumpEventQueue();

    expect(room.state.failure, isNull);
    expect(room.state.activeRoomId, isNull);
  });
}
