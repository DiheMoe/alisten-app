import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/core/realtime/room_transport.dart';
import 'package:alisten/features/room/application/room_controller.dart';
import 'package:alisten/features/room/application/room_state.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../room_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 11, 1, 12);
  late StreamController<List<ConnectivityResult>> connectivity;
  late FakeRoomTransportFactory factory;
  late ProviderContainer container;
  late RoomController controller;

  void openThenLose(FakeAsync async) {
    connectivity = StreamController.broadcast();
    factory = FakeRoomTransportFactory();
    container = ProviderContainer(
      overrides: [
        alistenApiProvider.overrideWithValue(
          FakeAlistenApi()..rooms = [roomListing()],
        ),
        credentialStoreProvider.overrideWithValue(
          FakeCredentialStore()..tickets['room-id'] = 'saved-ticket',
        ),
        roomTransportFactoryProvider.overrideWithValue(factory.call),
        ...roomDeviceOverrides(connectivity: connectivity.stream),
        roomNowProvider.overrideWithValue(() => now),
      ],
    );
    controller = container.read(roomControllerProvider.notifier);
    container.listen(connectivityStatusProvider, (_, _) {});
    unawaited(controller.openRoom('listen'));
    async.flushMicrotasks();
    factory.last.emitHello();
    async.flushMicrotasks();
    factory.last.disconnect();
    async.flushMicrotasks();
  }

  void finish(FakeAsync async) {
    container.dispose();
    unawaited(connectivity.close());
    async.flushMicrotasks();
  }

  test(
    'while waiting to reconnect, checks connect once and never sync or restart',
    () {
      fakeAsync((async) {
        openThenLose(async);
        final transport = factory.last;
        expect(controller.state.status, RoomConnectionStatus.reconnecting);
        expect(
          controller.state.nextRetryAt,
          now.add(transport.retryIn),
          reason: 'measured on the injected clock',
        );

        for (var i = 0; i < 10; i++) {
          unawaited(controller.checkConnection());
          connectivity.add([
            i.isEven ? ConnectivityResult.wifi : ConnectivityResult.mobile,
          ]);
          async.flushMicrotasks();
        }

        expect(transport.connectAttempts, 2);
        expect(transport.syncCalls, 0);
        expect(transport.restartCalls, 0);
        expect(controller.state.nextRetryAt, isNull);
        finish(async);
      });
    },
  );

  test('an unreachable server is retried after the backoff, not in a loop '
      'driven by checks on every room change (the ended playback plan)', () {
    fakeAsync((async) {
      openThenLose(async);
      final transport = factory.last..failAttempts = true;
      var changes = 0;
      container.listen(roomControllerProvider, (_, _) {
        // 设上限：出现反馈循环时让测试失败，而不是一直挂起。
        if (++changes < 100) unawaited(controller.checkConnection());
      });

      unawaited(controller.checkConnection());
      async.elapse(const Duration(seconds: 1));

      expect(transport.connectAttempts, 2);
      expect(changes, lessThan(10));
      async.elapse(transport.retryIn - const Duration(seconds: 1));
      expect(transport.connectAttempts, 3, reason: 'next attempt at backoff');
      expect(transport.syncCalls, 0);
      expect(transport.restartCalls, 0);

      connectivity.add([ConnectivityResult.wifi]);
      async.flushMicrotasks();
      expect(
        transport.connectAttempts,
        4,
        reason: 'a network change allows one more immediate attempt',
      );
      async.elapse(const Duration(seconds: 1));
      expect(transport.connectAttempts, 4);
      finish(async);
    });
  });

  test('a network change while a reconnect is under way allows one '
      'immediate retry after it fails, and the state tells when one is '
      'allowed', () {
    fakeAsync((async) {
      openThenLose(async);
      final transport = factory.last;
      expect(controller.state.mayReconnectNow, isTrue);

      unawaited(controller.checkConnection());
      async.flushMicrotasks();
      expect(transport.connectAttempts, 2);
      expect(controller.state.mayReconnectNow, isFalse);

      connectivity.add([ConnectivityResult.wifi]);
      async.flushMicrotasks();
      expect(transport.connectAttempts, 2, reason: 'an attempt is under way');
      expect(controller.state.mayReconnectNow, isTrue);

      transport.disconnect();
      async.flushMicrotasks();
      expect(controller.state.nextRetryAt, isNotNull);
      unawaited(controller.checkConnection());
      async.flushMicrotasks();
      expect(transport.connectAttempts, 3);
      expect(controller.state.mayReconnectNow, isFalse);

      transport.disconnect();
      async.flushMicrotasks();
      unawaited(controller.checkConnection());
      async.flushMicrotasks();
      expect(transport.connectAttempts, 3, reason: 'one per network change');
      finish(async);
    });
  });

  test('a last room not restored while offline is restored once when '
      'the network returns', () async {
    fakeAsync((async) {
      connectivity = StreamController.broadcast();
      factory = FakeRoomTransportFactory();
      final api = FakeAlistenApi()
        ..rooms = [roomListing()]
        ..getRoomError = const ApiException(
          code: LocalErrorCodes.network,
          message: '网络请求失败，请检查网络后重试。',
          status: null,
        );
      container = ProviderContainer(
        overrides: [
          alistenApiProvider.overrideWithValue(api),
          credentialStoreProvider.overrideWithValue(
            FakeCredentialStore()..tickets['room-id'] = 'saved-ticket',
          ),
          roomTransportFactoryProvider.overrideWithValue(factory.call),
          ...roomDeviceOverrides(
            connectivity: connectivity.stream,
            lastRoom: FakeLastRoomStore('listen'),
          ),
          roomNowProvider.overrideWithValue(() => now),
        ],
      );
      controller = container.read(roomControllerProvider.notifier);
      container.listen(connectivityStatusProvider, (_, _) {});
      unawaited(controller.restoreLastRoom());
      async.flushMicrotasks();
      expect(api.getRoomCalls, 1);
      expect(controller.state.failure, RoomFailure.unavailable);
      expect(factory.transports, isEmpty);

      api.getRoomError = null;
      connectivity
        ..add([ConnectivityResult.wifi])
        ..add([ConnectivityResult.wifi, ConnectivityResult.mobile]);
      async.flushMicrotasks();

      expect(api.getRoomCalls, 2, reason: 'one retry per network change');
      expect(factory.roomIds, ['room-id']);
      factory.last.emitHello();
      async.flushMicrotasks();
      expect(controller.state.status, RoomConnectionStatus.open);
      expect(controller.state.failure, isNull);

      connectivity.add([ConnectivityResult.mobile]);
      async.flushMicrotasks();
      expect(api.getRoomCalls, 2);
      expect(factory.transports, hasLength(1));
      finish(async);
    });
  });

  test('a last room asked for while the server changes is not restored '
      'when the network returns', () async {
    fakeAsync((async) {
      connectivity = StreamController.broadcast();
      factory = FakeRoomTransportFactory();
      final api = FakeAlistenApi()..rooms = [roomListing()];
      final lastRoom = FakeLastRoomStore();
      container = ProviderContainer(
        overrides: [
          alistenApiProvider.overrideWithValue(api),
          credentialStoreProvider.overrideWithValue(
            FakeCredentialStore()..tickets['room-id'] = 'saved-ticket',
          ),
          roomTransportFactoryProvider.overrideWithValue(factory.call),
          ...roomDeviceOverrides(
            connectivity: connectivity.stream,
            lastRoom: lastRoom,
          ),
          roomNowProvider.overrideWithValue(() => now),
        ],
      );
      controller = container.read(roomControllerProvider.notifier);
      container.listen(connectivityStatusProvider, (_, _) {});
      unawaited(
        controller.leaveForServerChange(() {
          // 已改写当前服务器：最近房间换成新服务器上的房间。
          lastRoom.room = 'listen';
          return controller.restoreLastRoom();
        }),
      );
      async.flushMicrotasks();

      connectivity.add([ConnectivityResult.wifi]);
      async.flushMicrotasks();

      expect(api.getRoomCalls, 0);
      expect(factory.transports, isEmpty);
      finish(async);
    });
  });
}
