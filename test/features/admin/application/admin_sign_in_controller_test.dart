import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../admin_test_doubles.dart';

const _unauthorized = ApiException(
  code: 'UNAUTHORIZED',
  message: 'token invalid',
  status: 401,
);
const _network = ApiException(
  code: 'NETWORK',
  message: '网络请求失败，请检查网络后重试。',
  status: null,
);

void main() {
  late FakeAdminApi api;
  late ProviderContainer container;

  AdminSignInController controller() =>
      container.read(adminSignInControllerProvider.notifier);
  AdminSignInState state() => container.read(adminSignInControllerProvider);

  bool? submit(FakeAsync async, String token) {
    bool? result;
    unawaited(controller().submit(token).then((value) => result = value));
    async.flushMicrotasks();
    return result;
  }

  void open() {
    api = FakeAdminApi();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(baseUrl: 'https://livehouse.dihe.moe', isRelease: false),
        ),
        adminApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    container.listen(adminSignInControllerProvider, (_, _) {});
  }

  test('three tokens refused in a row hold the button for 30 seconds, '
      'counted down each second', () {
    fakeAsync((async) {
      open();
      api.listRoomsError = _unauthorized;

      for (var attempt = 1; attempt <= 3; attempt++) {
        expect(submit(async, 't'), isFalse);
        expect(state().error, '管理 token 无效');
        expect(
          state().cooldownSeconds,
          attempt < 3 ? 0 : 30,
          reason: 'attempt $attempt',
        );
      }
      expect(adminFailuresBeforeCooldown, 3);
      expect(adminCooldown, const Duration(seconds: 30));

      expect(submit(async, 't'), isFalse);
      expect(api.listRoomsCalls, 3);

      async.elapse(const Duration(seconds: 1));
      expect(state().cooldownSeconds, 29);
      expect(submit(async, 't'), isFalse);
      expect(api.listRoomsCalls, 3);

      async.elapse(const Duration(seconds: 30));
      expect(state().cooldownSeconds, 0);
      expect(async.periodicTimerCount, 0);

      submit(async, 't');
      expect(api.listRoomsCalls, 4);
      expect(state().cooldownSeconds, 0, reason: 'the count started over');
    });
  });

  test('a token taken starts the count of refusals over', () {
    fakeAsync((async) {
      open();
      api.listRoomsError = _unauthorized;
      submit(async, 't');
      submit(async, 't');

      api.listRoomsError = null;
      expect(submit(async, 't'), isTrue);
      expect(state().error, isNull);
      expect(container.read(adminSessionProvider).active, isTrue);

      api.listRoomsError = _unauthorized;
      submit(async, 't');
      submit(async, 't');

      expect(state().cooldownSeconds, 0);
      expect(api.listRoomsCalls, 5);
    });
  });

  test('network failures are not counted', () {
    fakeAsync((async) {
      open();
      api.listRoomsError = _network;

      for (var attempt = 1; attempt <= 3; attempt++) {
        expect(submit(async, 't'), isFalse);
      }

      expect(state().cooldownSeconds, 0);
      expect(state().error, '网络请求失败，请检查网络后重试。');
      submit(async, 't');
      expect(api.listRoomsCalls, 4);
    });
  });

  test('an empty token is not sent', () {
    fakeAsync((async) {
      open();

      expect(submit(async, '   '), isFalse);

      expect(api.listRoomsCalls, 0);
      expect(state().busy, isFalse);
    });
  });

  test('a token being verified is not sent again, and the button is busy '
      'meanwhile', () {
    fakeAsync((async) {
      open();
      api.listRoomsGate = Completer();

      bool? first;
      unawaited(controller().submit('t').then((value) => first = value));
      async.flushMicrotasks();
      expect(state().busy, isTrue);
      expect(submit(async, 't'), isFalse);
      expect(api.listRoomsCalls, 1);

      api.listRoomsGate!.complete();
      async.flushMicrotasks();
      expect(first, isTrue);
      expect(state().busy, isFalse);
    });
  });

  test('submitting again clears the notice the session ended with', () {
    fakeAsync((async) {
      open();
      container
          .read(adminSessionProvider.notifier)
          .end(notice: adminTokenExpiredText);
      api.listRoomsError = _unauthorized;

      submit(async, 't');

      expect(container.read(adminSessionProvider).notice, isNull);
      expect(state().error, adminTokenInvalidText);
    });
  });

  test('a controller disposed while counting down stops the countdown', () {
    fakeAsync((async) {
      open();
      api.listRoomsError = _unauthorized;
      for (var attempt = 1; attempt <= 3; attempt++) {
        submit(async, 't');
      }
      expect(async.periodicTimerCount, 1);

      container.dispose();
      async.flushMicrotasks();

      expect(async.periodicTimerCount, 0);
    });
  });
}
