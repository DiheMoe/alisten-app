import 'dart:async';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:alisten/features/account/index.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';
import '../../server/server_test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late ProviderContainer container;
  late AccountController account;

  IdentityState identity() => container.read(identityControllerProvider);

  Future<void> open([
    Map<String, Object> stored = const {},
    CredentialStore Function(String serverId)? stores,
  ]) async {
    container = ProviderContainer(
      overrides: [
        ...alistenWiring(await loadPreferences(stored)),
        alistenApiProvider.overrideWithValue(api),
        credentialStoreFactoryProvider.overrideWithValue(
          stores ?? (_) => credentials,
        ),
        roomTransportFactoryProvider.overrideWithValue(
          FakeRoomTransportFactory().call,
        ),
        connectivityStatusProvider.overrideWith((ref) => const Stream.empty()),
      ],
    );
    addTearDown(container.dispose);
    account = container.read(accountControllerProvider);
  }

  setUp(() {
    api = FakeAlistenApi();
    credentials = FakeCredentialStore()..memberToken = 'guest-token';
  });

  group('login', () {
    test('checks the input before sending anything', () async {
      await open();

      final result = await account.login(
        username: 'Mao',
        password: 'password1',
      );

      expect(result, isA<MutationNotSent<Account>>());
      expect(api.loginCalls, 0);
    });

    test(
      'sends a saved device credential only when it is well formed',
      () async {
        await open();
        credentials.loginDevices['mao'] = deviceCredential;
        await account.login(username: 'mao', password: 'password1');
        expect(api.lastLogin?.device, deviceCredential);

        credentials
          ..memberToken = 'guest-token'
          ..loginDevices['mao'] = 'not-a-credential';
        api.account = null;
        await account.login(username: 'mao', password: 'password1');
        expect(api.lastLogin?.device, isNull);
      },
    );

    test('keeps the issued device credential and adopts the session', () async {
      await open();

      final result = await account.login(
        username: 'mao',
        password: 'password1',
      );

      expect(result, isA<MutationSucceeded<Account>>());
      expect(credentials.loginDevices['mao'], issuedDevice);
      expect(credentials.memberToken, 'account-token');
      expect(identity().account?.username, 'mao');
    });

    for (final (code, text) in [
      ('INVALID_CREDENTIALS', wrongCredentialsText),
      ('UNAUTHORIZED', '身份已更新，请再登录一次'),
    ]) {
      test('$code is told as "$text"', () async {
        await open();
        api.loginError = ApiException(code: code, message: '服务端', status: 401);

        final result = await account.login(
          username: 'mao',
          password: 'password1',
        );

        expect(result, isA<MutationFailed<Account>>());
        expect((result as MutationFailed<Account>).message, text);
      });
    }

    test('a server switch while the device credential is read sends '
        'nothing to either server', () async {
      final other = FakeCredentialStore();
      await open(const {}, (id) => id == serverB.id ? other : credentials);
      final gate = Completer<void>();
      credentials
        ..loginDevices['mao'] = deviceCredential
        ..readLoginDeviceGate = gate;

      final pending = account.login(username: 'mao', password: 'password1');
      await pumpEventQueue();
      final servers = container.read(serverDirectoryProvider.notifier);
      await servers.add(serverB);
      await servers.setCurrent(serverB.id);
      expect(container.read(credentialStoreProvider), same(other));
      gate.complete();
      final result = await pending;

      expect((result as MutationNotSent<Account>).message, '服务器已经切换，这次操作没有完成。');
      expect(api.loginCalls, 0);
      expect(credentials.writeLoginDeviceCalls, 0);
      expect(other.writeLoginDeviceCalls, 0);
      expect(credentials.memberToken, 'guest-token');
    });

    test('rate limiting is not sent and says when to try again', () async {
      await open();
      api.loginError = const ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
        retryAfter: Duration(seconds: 30),
      );

      final result = await account.login(
        username: 'mao',
        password: 'password1',
      );

      expect((result as MutationNotSent<Account>).message, '请求太频繁，请 30 秒后再试');
    });
  });

  group('register', () {
    test('moves the local email into the new account', () async {
      await open({'alisten.email': 'guest@example.com'});
      await container.read(identityControllerProvider.notifier).restore();

      final result = await account.register(
        username: 'mao',
        password: 'password1',
      );

      expect(result, isA<MutationSucceeded<Account>>());
      expect(identity().account?.username, 'mao');
      expect(api.updatedEmail, 'guest@example.com');
      expect(container.read(settingsControllerProvider).value.email, '');
      expect(identity().account?.email, 'guest@example.com');
    });

    test('an email the server refuses is dropped for good', () async {
      await open({'alisten.email': 'not-an-email'});
      api.updateMeError = const ApiException(
        code: 'INVALID_ARGUMENT',
        message: '邮箱格式不对',
        status: 400,
      );

      await account.register(username: 'mao', password: 'password1');

      expect(container.read(settingsControllerProvider).value.email, '');
    });

    test('an email that could not be sent is kept for later', () async {
      await open({'alisten.email': 'guest@example.com'});
      api.updateMeError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      await account.register(username: 'mao', password: 'password1');

      expect(
        container.read(settingsControllerProvider).value.email,
        'guest@example.com',
      );
    });

    test(
      'a closed registration is told and the capabilities are re-read',
      () async {
        await open();
        api.registerError = const ApiException(
          code: 'FORBIDDEN',
          message: '站点关闭了注册',
          status: 403,
        );
        // 保持监听，否则 autoDispose 的 provider 读完就释放，证明不了失效。
        final sub = container.listen(siteCapabilitiesProvider, (_, _) {});
        addTearDown(sub.close);
        await container.read(siteCapabilitiesProvider.future);

        final result = await account.register(
          username: 'mao',
          password: 'password1',
        );

        expect(
          (result as MutationFailed<Account>).message,
          registrationClosedText,
        );
        await container.read(siteCapabilitiesProvider.future);
        expect(api.getSiteCalls, 2);
      },
    );
  });

  group('logout', () {
    test('a network failure keeps the account', () async {
      await open();
      await account.login(username: 'mao', password: 'password1');
      api.logoutError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      final result = await account.logout();

      expect((result as MutationFailed<void>).message, logoutFailedText);
      expect(identity().account?.username, 'mao');
    });

    test('signs out and becomes a guest', () async {
      await open();
      await account.login(username: 'mao', password: 'password1');

      final result = await account.logout();

      expect(result, isA<MutationSucceeded<void>>());
      expect(identity().account, isNull);
      expect(credentials.loginDevices['mao'], issuedDevice);
    });
  });

  group('changePassword', () {
    for (final (code, text) in [
      ('INVALID_CREDENTIALS', wrongCurrentPasswordText),
      ('CONFLICT', '这个账号还没有密码，先设置用户名和密码'),
    ]) {
      test('$code is told as "$text"', () async {
        await open();
        api.changePasswordError = ApiException(
          code: code,
          message: '服务端',
          status: 401,
        );

        final result = await account.changePassword(
          current: 'password1',
          next: 'password2',
        );

        expect((result as MutationFailed<void>).message, text);
      });
    }

    test('a new password out of the rule is not sent', () async {
      await open();

      final result = await account.changePassword(
        current: 'password1',
        next: 'short',
      );

      expect(result, isA<MutationNotSent<void>>());
      expect(api.changePasswordCalls, 0);
    });
  });

  group('failure mapping', () {
    test('login CONFLICT is told and refreshes the profile', () async {
      await open();
      api.loginError = const ApiException(
        code: 'CONFLICT',
        message: '服务端',
        status: 409,
      );
      final before = api.getMeCalls;

      final result = await account.login(
        username: 'mao',
        password: 'password1',
      );
      await pumpEventQueue();

      expect((result as MutationFailed<Account>).message, '已经登录了账号');
      expect(api.getMeCalls, greaterThan(before));
    });

    test('login with a lost answer is unknown', () async {
      await open();
      api.loginError = const ApiException(
        code: LocalErrorCodes.network,
        message: '网络请求失败，请检查网络后重试。',
        status: null,
      );

      final result = await account.login(
        username: 'mao',
        password: 'password1',
      );

      expect(result, isA<MutationUnknown<Account>>());
    });

    test(
      'register CONFLICT carries the server message and refreshes',
      () async {
        await open();
        api.registerError = const ApiException(
          code: 'CONFLICT',
          message: '用户名已被占用',
          status: 409,
        );
        final before = api.getMeCalls;

        final result = await account.register(
          username: 'mao',
          password: 'password1',
        );
        await pumpEventQueue();

        expect((result as MutationFailed<Account>).message, '用户名已被占用');
        expect(api.getMeCalls, greaterThan(before));
      },
    );

    test('register rate limiting says when to try again', () async {
      await open();
      api.registerError = const ApiException(
        code: 'RATE_LIMITED',
        message: '请求太频繁，请稍后再试。',
        status: 429,
        retryAfter: Duration(seconds: 10),
      );

      final result = await account.register(
        username: 'mao',
        password: 'password1',
      );

      expect((result as MutationNotSent<Account>).message, '请求太频繁，请 10 秒后再试');
    });

    test('register does not throw when the member cannot be read', () async {
      await open();
      credentials
        ..memberToken = null
        ..readMemberTokenError = Exception('keystore');

      final result = await account.register(
        username: 'mao',
        password: 'password1',
      );

      expect(result, isA<MutationNotSent<Account>>());
    });

    test('logout answered UNAUTHORIZED still signs out', () async {
      await open();
      await account.login(username: 'mao', password: 'password1');
      api.logoutError = const ApiException(
        code: 'UNAUTHORIZED',
        message: '服务端',
        status: 401,
      );

      final result = await account.logout();

      expect(result, isA<MutationSucceeded<void>>());
      expect(identity().account, isNull);
    });

    test(
      'changePassword UNAUTHORIZED tells a registered user signed out',
      () async {
        await open();
        await account.login(username: 'mao', password: 'password1');
        api.changePasswordError = const ApiException(
          code: 'UNAUTHORIZED',
          message: '服务端',
          status: 401,
        );

        final result = await account.changePassword(
          current: 'password1',
          next: 'password2',
        );

        expect((result as MutationFailed<void>).message, signedOutNotice);
      },
    );

    test('changePassword UNAUTHORIZED after a server switch leaves the new '
        "server's identity alone", () async {
      final other = FakeCredentialStore();
      await open(const {}, (id) => id == serverB.id ? other : credentials);
      final gate = Completer<void>();
      api
        ..changePasswordGate = gate
        ..changePasswordError = unauthorized;

      final pending = account.changePassword(
        current: 'password1',
        next: 'password2',
      );
      await pumpEventQueue();
      final servers = container.read(serverDirectoryProvider.notifier);
      await servers.add(serverB);
      await servers.setCurrent(serverB.id);
      gate.complete();
      final result = await pending;

      expect((result as MutationFailed<void>).message, '服务器已经切换，这次操作没有完成。');
      expect(api.createMemberCalls, 0);
      expect(other.memberToken, isNull);
      expect(other.deleteMemberCalls, 0);
    });

    test(
      'changePassword UNAUTHORIZED tells a guest the identity renewed',
      () async {
        await open();
        api.changePasswordError = const ApiException(
          code: 'UNAUTHORIZED',
          message: '服务端',
          status: 401,
        );

        final result = await account.changePassword(
          current: 'password1',
          next: 'password2',
        );

        expect((result as MutationFailed<void>).message, identityRenewedNotice);
      },
    );
  });

  test('unreadable capabilities fall back to the server deciding', () async {
    await open();
    api.getSiteError = const ApiException(
      code: LocalErrorCodes.network,
      message: '网络请求失败，请检查网络后重试。',
      status: null,
    );

    final site = await container.read(siteCapabilitiesProvider.future);

    expect(site.registrationOpen, SiteCapabilities.unknown.registrationOpen);
  });
}
